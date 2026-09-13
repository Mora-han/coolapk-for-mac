import AppKit
import CryptoKit
import Foundation

/// Remote image loading with a two level cache (memory + disk) and thumbnail downsampling.
@MainActor
public final class ImageStore {
    public static let shared = ImageStore()

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

    public nonisolated static func normalize(_ url: String) -> String {
        guard !url.isEmpty else { return url }
        if url.hasPrefix("http://") {
            return "https://" + url.dropFirst("http://".count)
        }
        if url.hasPrefix("//") { return "https:" + url }
        return url
    }

    /// 从酷安图床的 `@宽x高.扩展名` 后缀里读出原始宽高比，无需下载图片。
    public nonisolated static func declaredAspect(of url: String) -> CGFloat? {
        guard let range = url.range(of: "@", options: .backwards) else { return nil }
        let suffix = url[range.upperBound...]
        guard let dot = suffix.range(of: ".") else { return nil }
        let parts = suffix[suffix.startIndex..<dot.lowerBound].split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), height > 0 else { return nil }
        guard width > 0, width < 40_000, height < 40_000 else { return nil }
        return CGFloat(width / height)
    }

    /// Rewrites the Coolapk CDN size suffix to fetch a smaller variant.
    public nonisolated static func resized(_ url: String, quality: Int) -> String {
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

    /// 返回图片的宽高比；未命中缓存时会触发一次加载。
    public func aspect(for rawURL: String, maxPixel: Int = 900) async -> CGFloat? {
        guard let image = await image(for: rawURL, maxPixel: maxPixel) else { return nil }
        guard image.size.height > 0 else { return nil }
        return image.size.width / image.size.height
    }

    public func image(for rawURL: String, maxPixel: Int = 1400) async -> NSImage? {
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
            if !ImageLoading.userAgent.isEmpty {
                request.setValue(ImageLoading.userAgent, forHTTPHeaderField: "User-Agent")
            }
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

    public static func downsample(data: Data, maxPixel: Int) -> NSImage? {
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

    public func diskCacheSize() async -> Int64 {
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

    public func clearDiskCache() async {
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
