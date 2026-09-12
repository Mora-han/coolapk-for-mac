import AppKit
import SwiftUI

/// 把 SwiftUI 的页面标题同步到 NSWindow，让标题栏与标签页显示当前所在位置。
struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        let resolved = (title.isEmpty || title == "酷安") ? "酷安" : "酷安 · \(title)"
        if window.title != resolved {
            window.title = resolved
        }
    }
}
