import AppKit
import SwiftUI

// MARK: - 小部件

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

/// 玻璃质感的信息徽标，用于作者、置顶、设备等元信息。
struct GlassTag: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
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

struct EmptyStateView: View {
    var title: String
    var message: String?
    var systemImage = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
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
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

/// 工具栏上的玻璃按钮（保留旧名字，内部改用统一的 GlassIconButton）。
struct ToolbarGlassButton: View {
    let systemImage: String
    var help: String = ""
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        GlassIconButton(systemImage: systemImage, help: help, size: 28, badge: badge, action: action)
    }
}
