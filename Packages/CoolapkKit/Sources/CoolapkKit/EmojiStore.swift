import AppKit

/// Coolapk emoji are plain `[name]` tokens in the message body; the images ship with the app.
public enum EmojiStore {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

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
