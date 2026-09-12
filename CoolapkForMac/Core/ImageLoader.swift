import AppKit
import CryptoKit
import Foundation

/// Coolapk emoji are plain `[name]` tokens in the message body; the images ship with the app.
enum EmojiStore {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func image(named name: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        let file = name.hasSuffix(".png") ? String(name.dropLast(4)) : name
        guard let url = Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "Emoji")
            ?? Bundle.main.url(forResource: file, withExtension: "png"),
            let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    static func hasEmoji(named name: String) -> Bool { image(named: name) != nil }
}

/// Remote image loading with a two level cache (memory + disk) and thumbnail downsampling.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, NSImage>()
    private var running: [String: Task<NSImage?, Never>] = [:]
    private let cacheDirectory: URL

    private init() {
        memory.countLimit = 260
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = base.appendingPathComponent("CoolapkImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    nonisolated static func normalize(_ url: String) -> String {
        guard !url.isEmpty else { return url }
        if url.hasPrefix("http://") {
            return "https://" + url.dropFirst("http://".count)
        }
        if url.hasPrefix("//") { return "https:" + url }
        return url
    }

    /// Rewrites the Coolapk CDN size suffix to fetch a smaller variant.
    nonisolated static func resized(_ url: String, quality: Int) -> String {
        guard quality < 2 else { return url }
        guard let range = url.range(of: "@", options: .backwards) else { return url }
        let suffix = url[range.upperBound...]
        guard suffix.contains("x"), let dot = suffix.range(of: ".") else { return url }
        let dimension = suffix[suffix.startIndex..<dot.lowerBound]
        let components = dimension.split(separator: "x")
        guard let width = Int(components.first ?? ""), let height = Int(components.last ?? "") else { return url }
        let scale = quality == 0 ? 0.35 : 0.7
        let newWidth = max(120, Int(Double(width) * scale))
        let newHeight = max(120, Int(Double(height) * scale))
        return String(url[..<range.lowerBound]) + "@\(newWidth)x\(newHeight).jpg"
    }

    func image(for rawURL: String, maxPixel: Int = 1400) async -> NSImage? {
        let url = ImageStore.normalize(rawURL)
        guard !url.isEmpty, let link = URL(string: url) else { return nil }
        let key = "\(url)|\(maxPixel)" as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if let existing = running[key as String] { return await existing.value }

        let task = Task<NSImage?, Never> { [cacheDirectory] in
            let diskURL = cacheDirectory.appendingPathComponent(ImageStore.hash(url) + "-\(maxPixel).img")
            if let data = try? Data(contentsOf: diskURL), let image = ImageStore.downsample(data: data, maxPixel: maxPixel) {
                return image
            }
            var request = URLRequest(url: link)
            // The image CDN only answers requests that carry the app user agent.
            request.setValue(CoolapkToken.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
            guard let (data, _) = try? await URLSession.shared.data(for: request), !data.isEmpty else { return nil }
            let image = ImageStore.downsample(data: data, maxPixel: maxPixel)
            if let encoded = image?.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: encoded),
               let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
                try? jpeg.write(to: diskURL)
            }
            return image
        }
        running[key as String] = task
        let image = await task.value
        running[key as String] = nil
        if let image { memory.setObject(image, forKey: key) }
        return image
    }

    static func downsample(data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func hash(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func diskCacheSize() async -> Int64 {
        await Task.detached {
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var total: Int64 = 0
            for file in files {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += Int64(size)
            }
            return total
        }.value
    }

    func clearDiskCache() async {
        let directory = cacheDirectory
        await Task.detached {
            let fileManager = FileManager.default
            if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                for file in files { try? fileManager.removeItem(at: file) }
            }
        }.value
        memory.removeAllObjects()
    }
}
