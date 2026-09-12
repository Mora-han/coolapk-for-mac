import AppKit
import SwiftUI

enum Palette {
    /// Coolapk brand green.
    static let brand = Color(red: 0.05, green: 0.72, blue: 0.38)
    static let brandSoft = Color(red: 0.05, green: 0.72, blue: 0.38).opacity(0.14)
    static let like = Color(red: 0.98, green: 0.28, blue: 0.36)
    static let star = Color(red: 1.0, green: 0.72, blue: 0.18)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
}

extension View {
    /// Liquid Glass panel used for floating bars and controls.
    func glassPanel(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        let glass: Glass = {
            var base: Glass = .regular
            if let tint { base = base.tint(tint) }
            if interactive { base = base.interactive() }
            return base
        }()
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.35), lineWidth: 0.6)
        )
    }
}

/// Formats counters the way Coolapk does (10,000 becomes 1.0万).
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

// MARK: - Images

struct RemoteImage: View {
    let url: String
    var maxPixel: Int = 1_200
    var contentMode: ContentMode = .fill
    var showsPlaceholder = true
    var cornerRadius: CGFloat = 0
    var quality: Int = 2

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if showsPlaceholder {
                ZStack {
                    Rectangle().fill(Color.primary.opacity(0.06))
                    if failed {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(.tertiary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                Color.clear
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            image = nil
            failed = false
            guard AppStore.shared.showImages, !url.isEmpty else {
                failed = true
                return
            }
            let link = ImageStore.resized(ImageStore.normalize(url), quality: quality)
            let loaded = await ImageStore.shared.image(for: link, maxPixel: maxPixel)
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

struct AvatarView: View {
    let url: String
    var size: CGFloat = 38
    var level: Int = 0

    var body: some View {
        RemoteImage(url: url, maxPixel: Int(size * 3.5), contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
    }
}

// MARK: - Small building blocks

struct CountLabel: View {
    let systemImage: String
    let count: Int
    var active = false
    var activeColor: Color = Palette.brand

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
            if count > 0 {
                Text(formatCount(count)).font(.system(size: 12.5))
            }
        }
        .foregroundStyle(active ? activeColor : Color.secondary)
    }
}

struct TagChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Palette.brand
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                }
                Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String?
    var systemImage = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct LoadingRow: View {
    var text = "正在加载…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote)
            Spacer()
            if let retry {
                Button("重试", action: retry).buttonStyle(.link).font(.footnote)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 12)
        .padding(.horizontal, 16)
    }
}

struct ToolbarGlassButton: View {
    let systemImage: String
    var help: String = ""
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13.5, weight: .medium))
                .frame(width: 26, height: 22)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Palette.like, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
