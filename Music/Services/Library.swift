import Foundation
import Observation

/// The local copy of the PocketBase library. Loads instantly from disk, then syncs.
@Observable
final class Library {
    enum SyncState: Equatable {
        case idle
        case syncing(done: Int, total: Int)
        case failed(String)
    }

    private(set) var tracks: [Track] = []
    private(set) var syncState: SyncState = .idle
    private(set) var lastSynced: Date?

    private let fileURL: URL = {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "library.json")
    }()

    private struct Snapshot: Codable {
        var tracks: [Track]
        var syncedAt: Date
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            tracks = snap.tracks
            lastSynced = snap.syncedAt
        }
    }

    func tracks(of kind: TrackKind) -> [Track] {
        tracks.filter { $0.type == kind }
    }

    func count(of kind: TrackKind) -> Int {
        tracks.reduce(0) { $0 + ($1.type == kind ? 1 : 0) }
    }

    var isSyncing: Bool {
        if case .syncing = syncState { return true }
        return false
    }

    func sync() async {
        guard !isSyncing else { return }
        syncState = .syncing(done: 0, total: max(tracks.count, 1))
        do {
            var all: [Track] = []
            var page = 1
            var totalPages = 1
            repeat {
                let result = try await PocketBase.fetchPage(page)
                all += result.items
                totalPages = result.totalPages
                syncState = .syncing(done: all.count, total: max(result.totalItems, 1))
                page += 1
            } while page <= totalPages

            tracks = all
            lastSynced = .now
            syncState = .idle
            persist()
        } catch is CancellationError {
            syncState = .idle
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    private func persist() {
        guard let lastSynced else { return }
        let snap = Snapshot(tracks: tracks, syncedAt: lastSynced)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
