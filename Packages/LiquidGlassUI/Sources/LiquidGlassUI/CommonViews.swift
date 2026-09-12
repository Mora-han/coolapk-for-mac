import AppKit
import SwiftUI

// MARK: - 小部件

public struct CountLabel: View {
    public init(systemImage: String, count: Int, active: Bool = false, activeColor: Color = Palette.brand) {
        self.systemImage = systemImage
        self.count = count
        self.active = active
        self.activeColor = activeColor
    }

    public let systemImage: String
    public let count: Int
    public var active = false
    public var activeColor: Color = Palette.brand

    public var body: some View {
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

public struct TagChip: View {
    public init(text: String, systemImage: String? = nil, tint: Color = Palette.brand, action: (() -> Void)? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public let text: String
    public var systemImage: String?
    public var tint: Color = Palette.brand
    public var action: (() -> Void)?

    public var body: some View {
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

/// 玻璃质感的信息徽标，用于作者、置顶、设备等元信息。
public struct GlassTag: View {
    public init(text: String, systemImage: String? = nil, tint: Color? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public let text: String
    public var systemImage: String?
    public var tint: Color?

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9.5, weight: .semibold))
            }
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        .glassChip(cornerRadius: 8, tint: nil)
    }
}

// MARK: - 状态视图

public struct EmptyStateView: View {
    public init(title: String, message: String? = nil, systemImage: String = "tray", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var title: String
    public var message: String?
    public var systemImage = "tray"
    public var actionTitle: String?
    public var action: (() -> Void)?

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.brand.opacity(0.75))
                .frame(width: 64, height: 64)
                .glassEffect(.regular, in: .circle)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                GlassActionButton(title: actionTitle, action: action)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

public struct LoadingRow: View {
    public var text = "正在加载…"

    public init(text: String = "正在加载…") {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

public struct ErrorBanner: View {
    public init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public let message: String
    public var retry: (() -> Void)?

    public var body: some View {
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
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

/// 工具栏上的玻璃按钮（保留旧名字，内部改用统一的 GlassIconButton）。
public struct ToolbarGlassButton: View {
    public init(systemImage: String, help: String = "", badge: Int = 0, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.badge = badge
        self.action = action
    }

    public let systemImage: String
    public var help: String = ""
    public var badge: Int = 0
    public let action: () -> Void

    public var body: some View {
        GlassIconButton(systemImage: systemImage, help: help, size: 28, badge: badge, action: action)
    }
}
