import AppKit
import SwiftUI

// MARK: - 基础玻璃面板

public extension View {
    /// Liquid Glass 面板，用于浮动条、悬浮控件与需要透出背景的容器。
    public func glassPanel(
        cornerRadius: CGFloat = Metrics.cardRadius,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        let glass: Glass = {
            var base: Glass = .regular
            if let tint { base = base.tint(tint) }
            if interactive { base = base.interactive() }
            return base
        }()
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    /// 更轻薄的玻璃，适合叠在内容之上的小徽标。
    public func glassChip(cornerRadius: CGFloat = 10, tint: Color? = nil) -> some View {
        let glass: Glass = {
            var base: Glass = .clear
            if let tint { base = base.tint(tint) }
            return base
        }()
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    /// 悬浮抬升效果：轻微放大 + 阴影，用于卡片 hover。
    public func hoverLift(_ hovering: Bool, scale: CGFloat = 1.006) -> some View {
        scaleEffect(hovering ? scale : 1)
            .shadow(color: .black.opacity(hovering ? 0.14 : 0), radius: hovering ? 10 : 0, y: hovering ? 3 : 0)
            .animation(.snappy(duration: 0.18), value: hovering)
    }
}

// MARK: - 玻璃胶囊（Tab 选择器）

/// 横向玻璃胶囊标签栏，选中项用 matchedGeometry 平滑过渡。
/// 只暴露 `isSelected` / `onSelect`，因此可以驱动任意类型的选中值。
public struct GlassPillBar<Item: Identifiable>: View {
    public init(items: [Item], title: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        icon: ((Item) -> String)? = nil,
        onSelect: @escaping (Item) -> Void) {
        self.items = items
        self.title = title
        self.isSelected = isSelected
        self.icon = icon
        self.onSelect = onSelect
    }

    public let items: [Item]
    public let title: (Item) -> String
    public let isSelected: (Item) -> Bool
    public var icon: ((Item) -> String)?
    public var onSelect: (Item) -> Void

    @Namespace private var namespace

    public var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        let active = isSelected(item)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { onSelect(item) }
                        } label: {
                            HStack(spacing: 5) {
                                if let icon {
                                    Image(systemName: icon(item)).font(.system(size: 11, weight: .medium))
                                }
                                Text(title(item))
                                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(active ? Palette.brand : Color.secondary)
                            .background {
                                if active {
                                    Capsule()
                                        .fill(Palette.brand.opacity(0.16))
                                        .matchedGeometryEffect(id: "glass-pill", in: namespace)
                                }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.clear.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, Metrics.gutter - 4)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 玻璃按钮

/// 圆形玻璃图标按钮，用于详情页、查看器与各类浮动控件。
public struct GlassIconButton: View {
    public init(systemImage: String, help: String = "", size: CGFloat = 28, tint: Color? = nil, badge: Int = 0, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.size = size
        self.tint = tint
        self.badge = badge
        self.action = action
    }

    public let systemImage: String
    public var help = ""
    public var size: CGFloat = 28
    public var tint: Color?
    public var badge: Int = 0
    public let action: () -> Void

    @State private var hovering = false

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .medium))
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Palette.like, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 7, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.snappy(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 主行动按钮：玻璃底 + 品牌色描边，用于“关注 / 登录 / 发送”。
public struct GlassActionButton: View {
    public init(title: String, systemImage: String? = nil, prominent: Bool = true, tint: Color = Palette.brand, minWidth: CGFloat = 72, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.tint = tint
        self.minWidth = minWidth
        self.action = action
    }

    public let title: String
    public var systemImage: String?
    public var prominent = true
    public var tint: Color = Palette.brand
    public var minWidth: CGFloat = 72
    public let action: () -> Void

    @State private var hovering = false

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11.5, weight: .semibold))
                }
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .frame(minWidth: minWidth)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .glassEffect((prominent ? Glass.regular.tint(tint) : Glass.regular).interactive(), in: .capsule)
        .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.snappy(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - 玻璃容器

/// 工具条式玻璃容器，可放多个控件并让它们自然融合（Liquid Glass morphing）。
public struct GlassBar<Content: View>: View {
    public init(cornerRadius: CGFloat = Metrics.panelRadius, spacing: CGFloat = 10, content: Content) {
        self.cornerRadius = cornerRadius
        self.spacing = spacing
        self.content = content
    }

    public var cornerRadius: CGFloat = Metrics.panelRadius
    public var spacing: CGFloat = 10
    @ViewBuilder public var content: Content

    public var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) { content }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

/// 悬浮在内容之上的玻璃页脚/页头容器。
public struct GlassFooter<Content: View>: View {
    public init(cornerRadius: CGFloat = Metrics.panelRadius, content: Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    public var cornerRadius: CGFloat = Metrics.panelRadius
    @ViewBuilder public var content: Content

    public var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 12)
    }
}
