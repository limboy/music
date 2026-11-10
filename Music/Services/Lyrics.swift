import Foundation
import Observation

struct LyricLine: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct Lyrics: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case library, lrclib }
    let lines: [LyricLine]
    let source: Source

    /// Index of the line that should be highlighted at `time`, or nil before the first line.
    func activeIndex(at time: TimeInterval) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}

// MARK: - LRC

enum LRCParser {
    private static let creditMarkers = ["lyrics by", "composed by", "arranged by", "produced by",
                                        "作词", "作曲", "编曲", "制作人", "詞：", "曲：", "词：", "作詞", "編曲"]

    static func parse(_ lrc: String) -> [LyricLine] {
        var result: [(TimeInterval, String)] = []
        let regex = #/\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/#

        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let stamps = line.matches(of: regex)
            guard !stamps.isEmpty else { continue }
            let text = line.replacing(regex, with: "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for m in stamps {
                let minutes = Double(m.output.1) ?? 0
                let seconds = Double(m.output.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                result.append((minutes * 60 + seconds, text))
            }
        }
        result.sort { $0.0 < $1.0 }

        // Drop the "Title - Artist" / credits preamble most LRC files open with.
        let cleaned = result.enumerated().filter { idx, item in
            guard item.0 < 30 else { return true }
            let lower = item.1.lowercased()
            if creditMarkers.contains(where: { lower.contains($0) }) { return false }
            if idx == 0 && item.0 < 1 && item.1.contains(" - ") { return false }
            return true
        }.map(\.element)

        return cleaned.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

// MARK: - Service

/// Lyrics come from the track's own `meta.lrc` first, then LRCLIB. Results (including misses) are cached on disk.
@Observable
final class LyricsService {
    enum State: Equatable {
        case loading
        case loaded(Lyrics)
        case unavailable
    }

    private(set) var states: [String: State] = [:]
    private var inFlight: Set<String> = []

    private let cacheDir: URL = {
        let caches = URL.cachesDirectory
        try? FileManager.default.removeItem(at: caches.appending(path: "lyrics"))   // old BetterLyrics cache
        let dir = caches.appending(path: "lyrics-lrclib", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private struct CacheEntry: Codable {
        let lyrics: Lyrics?
        let fetchedAt: Date
    }

    func state(for track: Track) -> State {
        states[track.id] ?? .loading
    }

    func load(_ track: Track) async {
        if let s = states[track.id], s != .loading { return }
        guard !inFlight.contains(track.id) else { return }
        inFlight.insert(track.id)
        defer { inFlight.remove(track.id) }

        // 1. Embedded LRC from PocketBase
        if let lrc = track.embeddedLRC {
            let lines = LRCParser.parse(lrc)
            if !lines.isEmpty {
                states[track.id] = .loaded(Lyrics(lines: lines, source: .library))
                return
            }
        }

        // Instrumental collections never have lyrics — skip the network.
        guard track.type == .song else {
            states[track.id] = .unavailable
            return
        }

        // 2. Disk cache (misses are re-tried after a week)
        let file = cacheDir.appending(path: "\(track.id).json")
        if let data = try? Data(contentsOf: file),
           let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
           entry.lyrics != nil || entry.fetchedAt.timeIntervalSinceNow > -7 * 86_400 {
            states[track.id] = entry.lyrics.map(State.loaded) ?? .unavailable
            return
        }

        // 3. LRCLIB
        states[track.id] = .loading
        switch await LRCLib.fetch(track) {
        case .found(let lines):
            let lyrics = Lyrics(lines: lines, source: .lrclib)
            states[track.id] = .loaded(lyrics)
            save(CacheEntry(lyrics: lyrics, fetchedAt: .now), to: file)
        case .notFound:
            states[track.id] = .unavailable
            save(CacheEntry(lyrics: nil, fetchedAt: .now), to: file)
        case .transientError:
            states[track.id] = .unavailable   // not cached; will retry next time
        }
    }

    private func save(_ entry: CacheEntry, to file: URL) {
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

// MARK: - LRCLIB client

/// https://lrclib.net — free, no key. Exact match via /api/get, then fuzzy /api/search.
enum LRCLib {
    enum Result { case found([LyricLine]), notFound, transientError }

    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
    }

    private static let base = URL(string: "https://lrclib.net/api")!

    static func fetch(_ track: Track) async -> Result {
        // Exact signature lookup
        var get = base.appending(path: "get")
        get.append(queryItems: [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.seconds))),
        ])
        switch await request(get, as: Record.self) {
        case .success(let record):
            if let lines = lines(from: record) { return .found(lines) }
        case .failure(let error):
            if error.transient { return .transientError }
        }

        // Fuzzy search: closest duration among results that have synced lyrics
        var search = base.appending(path: "search")
        search.append(queryItems: [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ])
        switch await request(search, as: [Record].self) {
        case .success(let records):
            let best = records
                .filter { $0.instrumental != true && !($0.syncedLyrics ?? "").isEmpty }
                .min { abs(($0.duration ?? 0) - track.seconds) < abs(($1.duration ?? 0) - track.seconds) }
            if let best, abs((best.duration ?? track.seconds) - track.seconds) <= 10, let lines = lines(from: best) {
                return .found(lines)
            }
            return .notFound
        case .failure(let error):
            return error.transient ? .transientError : .notFound
        }
    }

    private static func lines(from record: Record) -> [LyricLine]? {
        guard record.instrumental != true, let lrc = record.syncedLyrics, !lrc.isEmpty else { return nil }
        let lines = LRCParser.parse(lrc)
        return lines.isEmpty ? nil : lines
    }

    /// failure(true) = worth retrying later (network, 5xx, 429); failure(false) = definitive miss.
    private static func request<T: Decodable>(_ url: URL, as: T.Type) async -> Swift.Result<T, RequestError> {
        var req = URLRequest(url: url)
        req.setValue("Music/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(RequestError(transient: status == 429 || status >= 500)) }
            guard let value = try? JSONDecoder().decode(T.self, from: data) else { return .failure(RequestError(transient: false)) }
            return .success(value)
        } catch {
            return .failure(RequestError(transient: true))
        }
    }

    private struct RequestError: Error { let transient: Bool }
}
