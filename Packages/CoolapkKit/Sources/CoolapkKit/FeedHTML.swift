import AppKit
import Foundation

/// Where a tapped link inside a dynamic should take the reader.
public enum FeedLink: Hashable {
    case topic(String)
    case user(String)
    case feed(String)
    case product(String)
    case app(String)
    case collection(String)
    case dyh(String)
    case question(String)
    case vote(String)
    case page(String)
    case web(URL)
}

/// Converts the small HTML subset used by Coolapk messages into an attributed string with
/// inline emoji, tappable links and lightweight styling.
public enum FeedHTML {
    private static let cache = NSCache<NSString, NSAttributedString>()

    /// Cached variant used by list rows; the key covers content, size and appearance.
    public static func cachedAttributedString(html: String, fontSize: CGFloat, color: NSColor) -> NSAttributedString {
        let appearance = color == .labelColor ? "auto" : color.description
        let key = "\(fontSize)|\(appearance)|\(html)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let result = attributedString(html: html, fontSize: fontSize, textColor: color)
        cache.setObject(result, forKey: key)
        return result
    }

    public static func attributedString(
        html: String,
        fontSize: CGFloat,
        textColor: NSColor,
        emojiSize: CGFloat? = nil
    ) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 6

        let result = NSMutableAttributedString()
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]

        var boldDepth = 0
        var italicDepth = 0
        var strikeDepth = 0
        var linkURL: String?
        var index = html.startIndex

        func refreshFont() {
            var resolved: NSFont = font
            if boldDepth > 0 || italicDepth > 0 {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if boldDepth > 0 { traits.insert(.bold) }
                if italicDepth > 0 { traits.insert(.italic) }
                let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
                resolved = NSFont(descriptor: descriptor, size: fontSize) ?? font
            }
            attributes[.font] = resolved
        }

        func append(_ text: String) {
            guard !text.isEmpty else { return }
            refreshFont()
            var attrs = attributes
            if strikeDepth > 0 {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let linkURL, let url = URL(string: linkURL) {
                attrs[.link] = url
                attrs[.foregroundColor] = NSColor.controlAccentColor
            }
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        while index < html.endIndex {
            let character = html[index]
            if character == "<" {
                guard let close = html[index...].firstIndex(of: ">") else { break }
                let rawTag = String(html[html.index(after: index)..<close])
                index = html.index(after: close)
                // `apply` 只更新样式状态并返回是否需要换行；
                // 换行必须等 inout 访问结束后再写，否则会和 `append` 里的读取冲突。
                let needsNewline = apply(tag: rawTag.lowercased(), original: rawTag,
                                         boldDepth: &boldDepth, italicDepth: &italicDepth,
                                         strikeDepth: &strikeDepth, linkURL: &linkURL)
                if needsNewline { append("\n") }
                continue
            }

            // Emoji tokens look like [笑眼]; the images ship with the app bundle.
            if character == "[" {
                if let close = html[index...].firstIndex(of: "]"), html.distance(from: index, to: close) <= 20 {
                    let name = String(html[index...close])
                    if EmojiStore.hasEmoji(named: name) {
                        appendEmoji(named: name, to: result, attributes: attributes, fontSize: fontSize, emojiSize: emojiSize)
                        index = html.index(after: close)
                        continue
                    }
                }
            }

            var end = html.index(after: index)
            while end < html.endIndex, html[end] != "<", html[end] != "[" {
                end = html.index(after: end)
            }
            append(decodeEntities(String(html[index..<end])))
            index = end
        }

        return result
    }

    private static func appendEmoji(
        named name: String,
        to result: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any],
        fontSize: CGFloat,
        emojiSize: CGFloat?
    ) {
        guard let image = EmojiStore.image(named: name) else { return }
        let size = emojiSize ?? (fontSize + 4)
        let attachment = NSTextAttachment()
        attachment.image = image
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
        attachment.bounds = CGRect(x: 0, y: font.descender + 1.5, width: size, height: size)
        var attrs = attributes
        attrs.removeValue(forKey: .link)
        result.append(NSAttributedString(attachment: attachment, attributes: attrs))
    }

    /// 应用一个标签，返回 `true` 表示需要在当前光标处插入换行。
    private static func apply(
        tag: String,
        original: String,
        boldDepth: inout Int,
        italicDepth: inout Int,
        strikeDepth: inout Int,
        linkURL: inout String?
    ) -> Bool {
        let isClosing = tag.hasPrefix("/")
        let name = isClosing ? String(tag.dropFirst()) : String(tag.split(separator: " ").first ?? "")
        let bare = name.split(separator: " ").first.map(String.init) ?? name

        switch bare {
        case "br":
            return true
        case "p", "div":
            return isClosing
        case "b", "strong":
            boldDepth = max(0, boldDepth + (isClosing ? -1 : 1))
        case "i", "em":
            italicDepth = max(0, italicDepth + (isClosing ? -1 : 1))
        case "strike", "s", "del":
            strikeDepth = max(0, strikeDepth + (isClosing ? -1 : 1))
        case "a":
            if isClosing {
                linkURL = nil
            } else if let href = attribute(named: "href", in: original) {
                linkURL = resolve(href)
            }
        default:
            break
        }
        return false
    }

    private static func attribute(named name: String, in tag: String) -> String? {
        guard let range = tag.range(of: name, options: .caseInsensitive) else { return nil }
        let rest = tag[range.upperBound...]
        guard let equals = rest.firstIndex(of: "=") else { return nil }
        let value = rest[rest.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard let quote = value.first, quote == "\"" || quote == "'" else {
            return value.split(separator: " ").first.map(String.init)
        }
        let inner = value.dropFirst()
        guard let end = inner.firstIndex(of: quote) else { return String(inner) }
        return String(inner[inner.startIndex..<end])
    }

    /// Rewrites relative Coolapk links into a custom scheme the app can route.
    public static func resolve(_ href: String) -> String {
        let trimmed = decodeEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("/t/") {
            return route("topic", path: trimmed, key: "tag", stripQuery: true)
        }
        if trimmed.hasPrefix("/u/") {
            return route("user", path: trimmed, key: "uid", stripQuery: true)
        }
        if trimmed.hasPrefix("/feed/") {
            return route("feed", path: trimmed, key: "id", stripQuery: true)
        }
        if trimmed.hasPrefix("/product/") {
            return route("product", path: trimmed, key: "id", stripQuery: true)
        }
        if trimmed.hasPrefix("/apk/") {
            return route("app", path: trimmed, key: "id", stripQuery: true)
        }
        if trimmed.hasPrefix("/collection/") {
            return route("collection", path: trimmed, key: "id", stripQuery: true)
        }
        if trimmed.hasPrefix("/dyh/") {
            return route("dyh", path: trimmed, key: "id", stripQuery: true)
        }
        if trimmed.hasPrefix("/question/") {
            return route("question", path: trimmed, key: "id", stripQuery: true)
        }
        if trimmed.hasPrefix("/vote/") {
            return route("vote", path: trimmed, key: "id", stripQuery: true)
        }
        if trimmed.hasPrefix("/page") {
            return "coolapk://page?url=" + percent(trimmed)
        }
        if trimmed.hasPrefix("/") {
            return "coolapk://web?url=" + percent("https://www.coolapk.com" + trimmed)
        }
        return "coolapk://web?url=" + percent("https://www.coolapk.com/" + trimmed)
    }

    private static func route(_ host: String, path: String, key: String, stripQuery: Bool) -> String {
        var value = path
        if stripQuery, let question = value.firstIndex(of: "?") { value = String(value[..<question]) }
        value = value.split(separator: "/").dropFirst().joined(separator: "/")
        return "coolapk://\(host)?\(key)=" + percent(decodeEntities(value))
    }

    private static func percent(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    public static func route(from url: URL) -> FeedLink? {
        let text = url.absoluteString
        guard text.hasPrefix("coolapk://") else { return .web(url) }
        guard let components = URLComponents(string: text) else { return nil }
        let host = components.host ?? ""
        let value = components.queryItems?.first?.value ?? ""
        switch host {
        case "topic": return .topic(value)
        case "user": return .user(value)
        case "feed": return .feed(value)
        case "product": return .product(value)
        case "app": return .app(value)
        case "collection": return .collection(value)
        case "dyh": return .dyh(value)
        case "question": return .question(value)
        case "vote": return .vote(value)
        case "page": return .page(value)
        case "web":
            if let link = URL(string: value) { return .web(link) }
            return nil
        default: return nil
        }
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = text
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&middot;", "·"),
        ]
        for (key, value) in entities { output = output.replacingOccurrences(of: key, with: value) }
        return output
    }

    /// Plain text version, used for notifications and search previews.
    public static func plainText(_ html: String) -> String {
        var output = html
        output = output.replacingOccurrences(of: "<br>", with: " ")
        output = output.replacingOccurrences(of: "<br/>", with: " ")
        while let start = output.firstIndex(of: "<"), let end = output[start...].firstIndex(of: ">") {
            output.removeSubrange(start...end)
        }
        return decodeEntities(output)
    }
}
