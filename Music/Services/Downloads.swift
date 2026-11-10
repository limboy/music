import Foundation
import Network
import Observation

/// Keeps audio files on disk so tracks play without a connection.
/// Files live in Application Support/Downloads/<recordID>.<ext>, excluded from iCloud backup.
@Observable
final class Downloads {
    enum State: Equatable {
        case none
        case queued
        case downloading(Double)
        case done
        case failed
    }

    private(set) var states: [String: State] = [:]
    private(set) var totalBytes: Int64 = 0

    @ObservationIgnored private var pending: [Track] = []
    @ObservationIgnored private var active: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let maxConcurrent = 3
    @ObservationIgnored private var files: [String: URL] = [:]

    private let directory: URL = {
        var dir = URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    init() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for url in urls where !url.lastPathComponent.hasPrefix(".") {
            let id = url.deletingPathExtension().lastPathComponent
            files[id] = url
            states[id] = .done
        }
        recomputeSize()
    }

    // MARK: Queries

    func state(for track: Track) -> State { states[track.id] ?? .none }

    func isDownloaded(_ track: Track) -> Bool { files[track.id] != nil }

    func localURL(for track: Track) -> URL? { files[track.id] }

    func downloadedCount(in tracks: [Track]) -> Int { tracks.reduce(0) { $0 + (files[$1.id] != nil ? 1 : 0) } }

    var downloadedCount: Int { files.count }

    var inProgress: [String] {
        states.compactMap { id, s in
            switch s { case .queued, .downloading: id; default: nil }
        }
    }

    var isBusy: Bool { !active.isEmpty || !pending.isEmpty }

    // MARK: Actions

    func download(_ tracks: [Track]) {
        for t in tracks where files[t.id] == nil && active[t.id] == nil && !pending.contains(where: { $0.id == t.id }) {
            pending.append(t)
            states[t.id] = .queued
        }
        pump()
    }

    func cancel(_ track: Track) {
        pending.removeAll { $0.id == track.id }
        active[track.id]?.cancel()
        active[track.id] = nil
        if files[track.id] == nil { states[track.id] = nil }
        pump()
    }

    func cancelAll() {
        for t in pending { states[t.id] = nil }
        pending.removeAll()
        for (id, task) in active { task.cancel(); states[id] = nil }
        active.removeAll()
    }

    func remove(_ tracks: [Track]) {
        for t in tracks {
            cancel(t)
            if let url = files.removeValue(forKey: t.id) {
                try? FileManager.default.removeItem(at: url)
            }
            states[t.id] = nil
        }
        recomputeSize()
    }

    func removeAll() {
        cancelAll()
        for url in files.values { try? FileManager.default.removeItem(at: url) }
        files.removeAll()
        states.removeAll()
        recomputeSize()
    }

    /// Drop files for tracks that were deleted from PocketBase.
    func prune(keeping ids: Set<String>) {
        let stale = files.keys.filter { !ids.contains($0) }
        guard !stale.isEmpty else { return }
        for id in stale {
            if let url = files.removeValue(forKey: id) { try? FileManager.default.removeItem(at: url) }
            states[id] = nil
        }
        recomputeSize()
    }

    // MARK: Internals

    private func pump() {
        while active.count < maxConcurrent, !pending.isEmpty {
            let track = pending.removeFirst()
            active[track.id] = Task { [weak self] in
                await self?.run(track)
            }
        }
    }

    private func run(_ track: Track) async {
        let id = track.id
        states[id] = .downloading(0)
        let delegate = DownloadProgress { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.states[id] else { return }
                self.states[id] = .downloading(fraction)
            }
        }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: track.audioURL, delegate: delegate)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try Task.checkCancellation()
            let ext = (track.song as NSString).pathExtension
            let dest = directory.appending(path: "\(id).\(ext.isEmpty ? "mp3" : ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            files[id] = dest
            states[id] = .done
            recomputeSize()
            // Keep artwork warm for offline use.
            _ = await ImageCache.shared.image(for: track.coverURL(thumb: 100))
            _ = await ImageCache.shared.image(for: track.coverURL(thumb: 400))
            _ = await ImageCache.shared.image(for: track.coverURL(thumb: 600))
        } catch is CancellationError {
            states[id] = nil
        } catch let error as URLError where error.code == .cancelled {
            states[id] = nil
        } catch {
            states[id] = .failed
        }
        active[id] = nil
        pump()
    }

    private func recomputeSize() {
        totalBytes = files.values.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// Reports a single download's progress by observing the task URLSession creates for it.
nonisolated private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastReported = -1.0

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            guard let self else { return }
            let f = progress.fractionCompleted
            if f - self.lastReported >= 0.02 || f >= 1 {
                self.lastReported = f
                self.onProgress(f)
            }
        }
    }
}

/// Watches network reachability.
@Observable
final class Connectivity {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity"))
    }
}
