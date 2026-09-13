import AppKit
import SwiftUI

/// 原生侧边栏列表。
///
/// 内部就是 AppKit 的 source list：`NSTableView` 开 `style = .sourceList`，
/// 选中态交给系统按 source list 的模糊材质绘制——聚焦时是强调色玻璃，
/// 未聚焦时是中性半透明覆盖层。这里固定用未聚焦的那一种（App Store 的观感），
/// 见 `SidebarRowView`。
///
/// 行高、字号、图标尺寸、文本缩进都不自己定：`rowSizeStyle` 用系统默认值，
/// 由 `NSTableCellView` 按标准度量摆放它的 `textField` / `imageView`，
/// 系统怎么显示侧边栏，这里就怎么显示。
///
/// 表格背景必须保持 source list 的背景色：AppKit 只在背景没被改过时才用
/// 模糊材质画选中态，改成 `.clear` 之类会退化成普通实心高亮。
///
/// 之所以不用 SwiftUI 的 `List(selection:)`：它把选中态和焦点绑定，没有
/// 开放选择「始终用中性样式」的接口；侧边栏这类场合官方也一律走 AppKit。
public struct SourceListSidebar<Value: Hashable>: NSViewRepresentable {
    public struct Row: Identifiable, Equatable {
        public init(id: String, value: Value, title: String, systemImage: String, badge: Int = 0) {
            self.id = id
            self.value = value
            self.title = title
            self.systemImage = systemImage
            self.badge = badge
        }

        public let id: String
        public let value: Value
        public let title: String
        public let systemImage: String
        public let badge: Int
    }

    /// 分组标题行的复用标识。
    static var headerIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("sidebar.header") }

    public struct Section: Identifiable, Equatable {
        public init(id: String, title: String, rows: [Row]) {
            self.id = id
            self.title = title
            self.rows = rows
        }

        public let id: String
        public let title: String
        public let rows: [Row]
    }

    public init(sections: [Section], selection: Value?, onSelect: @escaping (Value) -> Void) {
        self.sections = sections
        self.selection = selection
        self.onSelect = onSelect
    }

    public var sections: [Section]
    public var selection: Value?
    public var onSelect: (Value) -> Void

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.gridStyleMask = []
        // 行高交给系统：rowSizeStyle 用默认值，表格会按 source list 的标准度量设置行高。
        tableView.rowSizeStyle = .default
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsColumnSelection = false
        tableView.focusRingType = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 8, right: 0)
        tableView.autoresizingMask = [.width]
        tableView.frame = scrollView.bounds
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        context.coordinator.apply(to: tableView)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        enum RowEntry {
            case header(String)
            case item(Row)
        }

        var parent: SourceListSidebar
        weak var tableView: NSTableView?
        private var entries: [RowEntry] = []
        private var signature = ""
        private var isSyncingSelection = false

        init(_ parent: SourceListSidebar) {
            self.parent = parent
        }

        func apply(to tableView: NSTableView) {
            let next = signature(of: parent.sections)
            if next != signature || entries.isEmpty {
                signature = next
                entries = parent.sections.flatMap { section -> [RowEntry] in
                    [.header(section.title)] + section.rows.map(RowEntry.item)
                }
                tableView.reloadData()
            }
            syncSelection(tableView)
        }

        private func signature(of sections: [Section]) -> String {
            sections.map { section in
                section.title + "|" + section.rows.map { "\($0.id)~\($0.title)~\($0.systemImage)~\($0.badge)" }.joined(separator: ";")
            }.joined(separator: "/")
        }

        private func syncSelection(_ tableView: NSTableView) {
            let target = entries.firstIndex { entry in
                if case let .item(row) = entry { return row.value == parent.selection }
                return false
            }
            let desired = target ?? -1
            guard tableView.selectedRow != desired else { return }
            isSyncingSelection = true
            if let target {
                tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
                tableView.scrollRowToVisible(target)
            } else {
                tableView.deselectAll(nil)
            }
            isSyncingSelection = false
        }

        // MARK: Data source

        public func numberOfRows(in tableView: NSTableView) -> Int {
            entries.count
        }

        // MARK: Delegate

        public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .header = entries[row] { return true }
            return false
        }

        public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            if case .header = entries[row] { return false }
            return true
        }

        public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SidebarRowView()
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch entries[row] {
            case let .header(title):
                // 分组标题：给一个只带 stringValue 的 NSTextField，系统会自动套用
                // group row 的字体、颜色与缩进。
                let field = tableView.makeView(withIdentifier: SourceListSidebar.headerIdentifier, owner: nil) as? NSTextField
                    ?? NSTextField(labelWithString: "")
                field.identifier = SourceListSidebar.headerIdentifier
                field.stringValue = title
                return field
            case let .item(entry):
                let cell = tableView.makeView(withIdentifier: SidebarItemCell.identifier, owner: nil) as? SidebarItemCell ?? SidebarItemCell()
                cell.identifier = SidebarItemCell.identifier
                cell.configure(title: entry.title, systemImage: entry.systemImage, badge: entry.badge)
                return cell
            }
        }

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection,
                  let tableView = notification.object as? NSTableView,
                  tableView.selectedRow >= 0,
                  tableView.selectedRow < entries.count,
                  case let .item(row) = entries[tableView.selectedRow]
            else { return }
            // 点侧栏等于「离开输入」：把 first responder 从搜索框收回列表。
            // 否则搜索框一直握着焦点，再次点它不会产生焦点变化，界面像没反应。
            if let window = tableView.window, window.firstResponder !== tableView {
                window.makeFirstResponder(tableView)
            }
            parent.onSelect(row.value)
        }
    }
}

// MARK: - Rows

/// 行视图：选中背景仍由系统的 source list 模糊材质绘制，只是不再随焦点切换成强调色。
///
/// `emphasized` 的语义是「相关视图持有 first responder」，系统据此在强调色与中性色之间
/// 二选一。App Store 的侧边栏常年是中性那一种，这里照做：不自己配色，
/// 只是把系统那套中性材质固定下来。
private final class SidebarRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

// MARK: - Cells

/// 侧边栏条目：图标 + 标题 + 徽标。
///
/// `textField` / `imageView` 两个出口交给 `NSTableCellView`，它按当前 `rowSizeStyle`
/// 用系统标准度量摆放并设置字体，所以这里不写任何尺寸常量；徽标是自己加的，
/// 所以在 `layout()` 里贴到右侧、并把标题宽度让出来。
private final class SidebarItemCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("sidebar.item")

    private let sidebarImageView = NSImageView()
    private let sidebarTextField = NSTextField(labelWithString: "")
    private let badge = SidebarBadgeView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        // 图标位由系统摆好，符号用系统给的原始尺寸绘制。
        sidebarImageView.imageScaling = .scaleProportionallyDown
        sidebarImageView.contentTintColor = .controlAccentColor

        sidebarTextField.lineBreakMode = .byTruncatingTail

        addSubview(sidebarImageView)
        addSubview(sidebarTextField)
        addSubview(badge)

        imageView = sidebarImageView
        textField = sidebarTextField
    }

    override func layout() {
        super.layout()

        let badgeSize = badge.intrinsicContentSize
        let badgeFrame = NSRect(
            x: bounds.maxX - 10 - badgeSize.width,
            y: bounds.midY - badgeSize.height / 2,
            width: badgeSize.width,
            height: badgeSize.height
        )
        if badge.frame != badgeFrame { badge.frame = badgeFrame }

        var titleFrame = sidebarTextField.frame
        let limit = badge.count > 0 ? badgeFrame.minX - 8 : bounds.maxX - 10
        if titleFrame.maxX > limit {
            titleFrame.size.width = max(0, limit - titleFrame.minX)
            if sidebarTextField.frame != titleFrame { sidebarTextField.frame = titleFrame }
        }
    }

    func configure(title: String, systemImage: String, badge count: Int) {
        sidebarTextField.stringValue = title
        sidebarImageView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        badge.count = count
    }
}

/// 数字徽标，系统红 + 白字（和邮件、信息的侧边栏一致）。
private final class SidebarBadgeView: NSView {
    private let font = NSFont.systemFont(ofSize: 10, weight: .bold)

    var count = 0 {
        didSet {
            guard count != oldValue else { return }
            isHidden = count <= 0
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private var text: String { count > 99 ? "99+" : "\(count)" }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isHidden = true
    }

    override var intrinsicContentSize: NSSize {
        guard count > 0 else { return NSSize(width: 0, height: 0) }
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: max(17, width + 10), height: 15)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard count > 0 else { return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.systemRed.setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
