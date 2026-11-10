import SwiftUI

enum TrackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case song, jazz, piano

    var id: String { rawValue }

    var title: String {
        switch self {
        case .song: "Songs"
        case .jazz: "Jazz"
        case .piano: "Piano"
        }
    }

    var accent: Color {
        switch self {
        case .song: Color(red: 1.00, green: 0.48, blue: 0.35)   // #FF7A59
        case .jazz: Color(red: 0.90, green: 0.71, blue: 0.40)   // #E5B567
        case .piano: Color(red: 0.62, green: 0.72, blue: 1.00)  // #9DB8FF
        }
    }
}

/// One record from the PocketBase `music` collection.
struct Track: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let singer: String
    let album: String
    let type: TrackKind
    let duration: String   // "mm:ss"
    let cover: String      // file name
    let song: String       // audio file name
    let created: String
    let meta: Meta?

    struct Meta: Codable, Hashable, Sendable {
        let lrc: String?
    }

    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var artist: String { singer.trimmingCharacters(in: .whitespacesAndNewlines) }

    var seconds: TimeInterval {
        let parts = duration.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    var embeddedLRC: String? {
        guard let lrc = meta?.lrc, !lrc.isEmpty else { return nil }
        return lrc
    }

    var audioURL: URL { PocketBase.fileURL(recordID: id, file: song) }

    func coverURL(thumb: Int? = 400) -> URL? {
        guard !cover.isEmpty else { return nil }
        return PocketBase.fileURL(recordID: id, file: cover, thumb: thumb)
    }

    var subtitle: String {
        album.isEmpty ? artist : "\(artist) · \(album)"
    }

    // Tolerant decoding: PocketBase sends empty strings / nulls for missing fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        singer = (try? c.decode(String.self, forKey: .singer)) ?? ""
        album = (try? c.decode(String.self, forKey: .album)) ?? ""
        type = (try? c.decode(TrackKind.self, forKey: .type)) ?? .song
        duration = (try? c.decode(String.self, forKey: .duration)) ?? "0:00"
        cover = (try? c.decode(String.self, forKey: .cover)) ?? ""
        song = (try? c.decode(String.self, forKey: .song)) ?? ""
        created = (try? c.decode(String.self, forKey: .created)) ?? ""
        meta = try? c.decode(Meta.self, forKey: .meta)
    }
}

extension TimeInterval {
    /// 3:07
    var clock: String {
        let v = Int(max(0, self.rounded(.down)))
        return "\(v / 60):" + String(format: "%02d", v % 60)
    }
}
