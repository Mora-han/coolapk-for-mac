import AppKit
import SwiftUI

/// Measurement helpers shared by the rich text view and the feed cards.
enum RichTextMeasure {
    static func layout(_ string: NSAttributedString, width: CGFloat, maxLines: Int) -> (height: CGFloat, truncated: Bool) {
        guard width > 1 else { return (0, false) }
        let storage = NSTextStorage(attributedString: string)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = maxLines
        container.lineBreakMode = maxLines > 0 ? .byTruncatingTail : .byWordWrapping
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let rect = manager.usedRect(for: container)

        var truncated = false
        if maxLines > 0 {
            let glyphRange = manager.glyphRange(for: container)
            let characterRange = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            truncated = characterRange.upperBound < string.length
        }
        return (ceil(rect.height), truncated)
    }

    static func height(_ string: NSAttributedString, width: CGFloat, maxLines: Int = 0) -> CGFloat {
        layout(string, width: width, maxLines: maxLines).height
    }
}

/// AppKit backed rich text view. TextKit handles selection, links, emoji attachments and
/// line truncation exactly like the system does, which keeps the layout native.
struct RichTextView: NSViewRepresentable {
    let attributed: NSAttributedString
    var maxLines: Int = 0
    var isSelectable = true
    var onLink: ((FeedLink) -> Void)?
    var onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RichTextContainer {
        let view = RichTextContainer()
        view.onLink = onLink
        view.onTap = onTap
        view.apply(attributed: attributed, maxLines: maxLines, isSelectable: isSelectable)
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: RichTextContainer, context: Context) {
        view.onLink = onLink
        view.onTap = onTap
        context.coordinator.parent = self
        view.apply(attributed: attributed, maxLines: maxLines, isSelectable: isSelectable)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RichTextContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 1 else { return nil }
        let height = RichTextMeasure.height(nsView.richAttributedString(), width: width, maxLines: maxLines)
        return CGSize(width: width, height: max(height, 1))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextView

        init(_ parent: RichTextView) { self.parent = parent }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            if let route = FeedHTML.route(from: url) {
                parent.onLink?(route)
                return true
            }
            return false
        }
    }
}

final class RichTextContainer: NSTextView {
    var onLink: ((FeedLink) -> Void)?
    var onTap: (() -> Void)?

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isRichText = true
        allowsUndo = false
        textContainerInset = .zero
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        usesFindBar = false
        linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: 0,
            .cursor: NSCursor.pointingHand,
        ]
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func richAttributedString() -> NSAttributedString {
        textStorage ?? NSAttributedString()
    }

    func apply(attributed: NSAttributedString, maxLines: Int, isSelectable: Bool) {
        self.isSelectable = isSelectable
        textContainer?.maximumNumberOfLines = maxLines
        textContainer?.lineBreakMode = maxLines > 0 ? .byTruncatingTail : .byWordWrapping
        if let storage = textStorage {
            if storage.isEqual(to: attributed) { return }
            let selected = selectedRange()
            storage.setAttributedString(attributed)
            if selected.location <= storage.length {
                setSelectedRange(NSRange(location: min(selected.location, storage.length), length: 0))
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer?.containerSize = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
    }

    /// Links stay clickable in non selectable cards: the character under the cursor is
    /// inspected for a link attribute, everything else falls through to the card action.
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isSelectable == false else {
            super.mouseUp(with: event)
            return
        }
        if let link = link(at: point), let route = FeedHTML.route(from: link) {
            onLink?(route)
        } else {
            onTap?()
        }
    }

    private func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let storage = textStorage else { return nil }
        let adjusted = NSPoint(x: point.x - textContainerInset.width, y: point.y - textContainerInset.height)
        let index = layoutManager.characterIndex(for: adjusted, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index >= 0, index < storage.length else { return nil }
        if let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL { return url }
        return nil
    }
}
