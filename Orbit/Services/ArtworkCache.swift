import ImageIO
import UIKit

/// Artwork loader for lists. Podcast covers are often 3000×3000 JPEGs of several MB; decoding
/// those at full size while scrolling makes lists stutter, and the system URL cache is too small
/// to keep them, so they re-download. This downsizes each cover once to the size it's shown at,
/// keeps it in memory, and stores the small copy on disk.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 80 * 1024 * 1024
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    /// Pixel sizes are rounded up to a few steps so one show doesn't get a copy per view size.
    static func bucket(_ pixels: CGFloat) -> Int {
        for step in [96, 192, 384, 768] where pixels <= CGFloat(step) { return step }
        return 1200
    }

    private func key(_ url: URL, _ size: Int) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in url.absoluteString.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return "\(String(hash, radix: 36))-\(size)"
    }

    /// Instant memory lookup, so rows scrolled back into view show their art with no flash.
    func cached(_ url: URL, size: Int) -> UIImage? {
        memory.object(forKey: key(url, size) as NSString)
    }

    func image(_ url: URL, size: Int) async -> UIImage? {
        let name = key(url, size)
        if let hit = memory.object(forKey: name as NSString) { return hit }
        let file = folder.appendingPathComponent(name).appendingPathExtension("jpg")
        if let image = Self.decode(file: file, size: size) {
            store(image, name)
            return image
        }
        let data: Data
        if url.isFileURL {
            guard let local = try? Data(contentsOf: url) else { return nil }
            data = local
        } else {
            guard let (remote, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            data = remote
        }
        guard let image = Self.decode(data: data, size: size) else { return nil }
        store(image, name)
        if let jpeg = image.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: file, options: .atomic) }
        return image
    }

    private func store(_ image: UIImage, _ name: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: name as NSString, cost: cost)
    }

    private static func decode(file: URL, size: Int) -> UIImage? {
        guard FileManager.default.fileExists(atPath: file.path),
              let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return thumbnail(source, size)
    }

    private static func decode(data: Data, size: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source, size)
    }

    /// Downsizes and fully decodes off the main thread, so drawing it costs nothing.
    private static func thumbnail(_ source: CGImageSource, _ size: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
