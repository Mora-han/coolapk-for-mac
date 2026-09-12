import AppKit

/// Coolapk emoji are plain `[name]` tokens in the message body; the images ship with the app.
public enum EmojiStore {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    /// 随 App 一起打包的表情名称（含方括号，如 `[笑眼]`），首次访问时扫描一次。
    public static let allNames: [String] = {
        let directory = Bundle.main.url(forResource: "Emoji", withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent("Emoji")
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    public static func image(named name: String) -> NSImage? {
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

    public static func hasEmoji(named name: String) -> Bool { image(named: name) != nil }
}
