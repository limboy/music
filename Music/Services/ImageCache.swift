import UIKit

/// In-memory decoded artwork, backed by URLCache on disk.
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    init() {
        memory.countLimit = 300
    }

    func cached(_ url: URL?) -> UIImage? {
        guard let url else { return nil }
        return memory.object(forKey: url as NSURL)
    }

    func image(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let task = inFlight[url] { return await task.value }

        let session = self.session
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return await Task.detached(priority: .userInitiated) {
                UIImage(data: data)?.preparingForDisplay()
            }.value
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}
