import Foundation

/// Minimal client for the public `music` collection on pb.limboy.me.
enum PocketBase {
    static let base = URL(string: "https://pb.limboy.me")!
    static let collection = "music"

    struct Page: Decodable {
        let page: Int
        let totalPages: Int
        let totalItems: Int
        let items: [Track]
    }

    static func fileURL(recordID: String, file: String, thumb: Int? = nil) -> URL {
        var url = base.appending(path: "api/files/\(collection)/\(recordID)/\(file)")
        if let thumb {
            url.append(queryItems: [URLQueryItem(name: "thumb", value: "\(thumb)x\(thumb)")])
        }
        return url
    }

    static func fetchPage(_ page: Int, perPage: Int = 200) async throws -> Page {
        var url = base.appending(path: "api/collections/\(collection)/records")
        url.append(queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "perPage", value: "\(perPage)"),
            URLQueryItem(name: "sort", value: "-created"),
        ])
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Page.self, from: data)
    }
}
