import AppKit
import SwiftUI

/// 全局配色与排版常量。所有界面统一从这里取值，方便整体换肤。
enum Palette {
    /// 酷安品牌绿。
    static let brand = Color(red: 0.05, green: 0.72, blue: 0.38)
    static let brandSoft = Color(red: 0.05, green: 0.72, blue: 0.38).opacity(0.14)
    static let like = Color(red: 0.98, green: 0.28, blue: 0.36)
    static let star = Color(red: 1.0, green: 0.72, blue: 0.18)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let hairline = Color.primary.opacity(0.06)
    static let fill = Color.primary.opacity(0.05)
}

enum Metrics {
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12
    static let gutter: CGFloat = 18
    static let cardSpacing: CGFloat = 10
    static let maxReadingWidth: CGFloat = 760
}

/// 计数器格式化，10,000 → 1.0万。
func formatCount(_ value: Int) -> String {
    if value >= 100_000_000 { return String(format: "%.1f亿", Double(value) / 100_000_000) }
    if value >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000) }
    if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
    return String(value)
}

func relativeTime(_ date: Date?) -> String {
    guard let date else { return "" }
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "刚刚" }
    if interval < 3_600 { return "\(Int(interval / 60))分钟前" }
    if interval < 86_400 { return "\(Int(interval / 3_600))小时前" }
    if interval < 86_400 * 7 { return "\(Int(interval / 86_400))天前" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

extension View {
    /// 统一的卡片底色（不使用玻璃，避免长列表滚动掉帧）。
    func cardBackground(cornerRadius: CGFloat = Metrics.cardRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.35), lineWidth: 0.6)
        )
    }

    /// 统一的阅读宽度约束。
    func readingWidth(_ extra: CGFloat = 140) -> some View {
        frame(maxWidth: min(Metrics.maxReadingWidth, AppStore.shared.contentWidth + extra))
            .frame(maxWidth: .infinity)
    }
}
