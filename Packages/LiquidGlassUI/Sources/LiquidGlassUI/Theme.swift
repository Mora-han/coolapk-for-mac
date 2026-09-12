import AppKit
import SwiftUI

/// 全局配色与排版常量。所有界面统一从这里取值，方便整体换肤。
public enum Palette {
    /// 酷安品牌绿。
    public static let brand = Color(red: 0.05, green: 0.72, blue: 0.38)
    public static let brandSoft = Color(red: 0.05, green: 0.72, blue: 0.38).opacity(0.14)
    public static let like = Color(red: 0.98, green: 0.28, blue: 0.36)
    public static let star = Color(red: 1.0, green: 0.72, blue: 0.18)
    public static let cardBackground = Color(nsColor: .controlBackgroundColor)
    /// 窗口级背景色，用作渐隐遮罩与画布底色。
    public static let canvas = Color(nsColor: .windowBackgroundColor)
    public static let separator = Color(nsColor: .separatorColor)
    public static let hairline = Color.primary.opacity(0.06)
    public static let fill = Color.primary.opacity(0.05)
}

public enum Metrics {
    public static let cardRadius: CGFloat = 16
    public static let panelRadius: CGFloat = 18
    public static let controlRadius: CGFloat = 12
    public static let gutter: CGFloat = 18
    public static let cardSpacing: CGFloat = 10
    public static let maxReadingWidth: CGFloat = 760
}

/// 计数器格式化，10,000 → 1.0万。
public func formatCount(_ value: Int) -> String {
    if value >= 100_000_000 { return String(format: "%.1f亿", Double(value) / 100_000_000) }
    if value >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000) }
    if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
    return String(value)
}

public func relativeTime(_ date: Date?) -> String {
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

public extension View {
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

    /// 浮动工具条背后的渐隐遮罩。
    ///
    /// 滚动内容靠近底部时会自然淡出，避免和玻璃条直接重叠产生视觉噪声，
    /// 同时保留玻璃的通透感。
    func floatingBarBackdrop(height: CGFloat = 108) -> some View {
        background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: Palette.canvas.opacity(0), location: 0),
                    .init(color: Palette.canvas.opacity(0.82), location: 0.5),
                    .init(color: Palette.canvas.opacity(0.97), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .allowsHitTesting(false)
        }
    }

    /// 统一的阅读宽度约束。
    func readingWidth(_ contentWidth: CGFloat, extra: CGFloat = 140) -> some View {
        frame(maxWidth: min(Metrics.maxReadingWidth, contentWidth + extra))
            .frame(maxWidth: .infinity)
    }
}
