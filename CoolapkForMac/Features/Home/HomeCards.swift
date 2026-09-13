import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

/// Top banner carousel of the home timeline.
struct BannerCarousel: View {
    let key: String
    let banners: [HomeBanner]
    let width: CGFloat

    @Environment(AppStore.self) private var store
    @State private var index = 0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(banners) { banner in
                            BannerTile(banner: banner, width: proxy.size.width)
                                .onTapGesture { store.openTarget(url: banner.url) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: Binding(get: { index }, set: { index = $0 ?? 0 }))
                .scrollIndicators(.hidden)
            }
            .frame(height: 108)

            if banners.count > 1 {
                HStack(spacing: 5) {
                    ForEach(banners.indices, id: \.self) { position in
                        Circle()
                            .fill(position == index ? Palette.brand : Color.secondary.opacity(0.28))
                            .frame(width: 5.5, height: 5.5)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassEffect(.clear, in: .capsule)
            }
        }
        .frame(width: width)
        .padding(10)
        .cardBackground(cornerRadius: 16)
    }
}

private struct BannerTile: View {
    let banner: HomeBanner
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: banner.image, maxPixel: 1_400, contentMode: .fill, cornerRadius: 12)
                .frame(width: width - 20, height: 108)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)
                .frame(height: 54)
                .allowsHitTesting(false)
            Text(banner.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .lineLimit(1)
        }
        .frame(width: width - 20, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Grid of quick entries (应用 / 话题 / 排行榜 shortcuts).
struct IconLinkGrid: View {
    let key: String
    let links: [HomeIconLink]
    let width: CGFloat

    @Environment(AppStore.self) private var store

    private var columns: Int { links.count > 8 ? 5 : min(max(links.count, 3), 5) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 14) {
            ForEach(links) { link in
                IconLinkCell(link: link) { store.openTarget(url: link.url) }
            }
        }
        .padding(14)
        .frame(width: width)
        .cardBackground(cornerRadius: 16)
    }
}

private struct IconLinkCell: View {
    let link: HomeIconLink
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            RemoteImage(url: link.image, maxPixel: 200, contentMode: .fill, cornerRadius: 11)
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 6, y: 2)
            Text(link.title)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.brand.opacity(0.09))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .scaleEffect(hovering ? 1.05 : 1)
        .animation(.snappy(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Horizontal scroller of image sections.
struct SectionScroller: View {
    let key: String
    let sections: [HomeSection]
    let width: CGFloat

    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("推荐专题")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImage(url: section.style, maxPixel: 700, contentMode: .fill, cornerRadius: 12)
                                .frame(width: 190, height: 112)
                                .clipped()
                            Text(section.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                            if !section.subtitle.isEmpty {
                                Text(section.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 190)
                        .contentShape(Rectangle())
                        .onTapGesture { store.openTarget(url: section.url) }
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 14)
        .frame(width: width, alignment: .leading)
        .cardBackground(cornerRadius: 16)
    }
}

struct TextCardView: View {
    let key: String
    let text: String
    let width: CGFloat

    var body: some View {
        HStack {
            Text(text).font(.system(size: 13.5, weight: .semibold))
            Spacer()
        }
        .padding(14)
        .frame(width: width)
        .cardBackground(cornerRadius: 16)
    }
}

// MARK: - Product / topic / user cards

struct ProductCardView: View {
    let item: ProductItem
    let width: CGFloat

    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.logo, maxPixel: 260, contentMode: .fill, cornerRadius: 12)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if !item.score.isEmpty, item.score != "0" {
                        Text(item.score).font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Palette.brandSoft, in: Capsule())
                            .foregroundStyle(Palette.brand)
                    }
                }
                if !item.description.isEmpty {
                    Text(FeedHTML.plainText(item.description))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: width)
        .cardBackground(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture { store.selection = .discover("product-\(item.id)", item.id) }
    }
}

struct TopicCardView: View {
    let item: TopicItem
    let width: CGFloat

    @Environment(AppStore.self) private var store
    /// 点过关注按钮后以本地状态为准，不用等列表刷新。
    @State private var followOverride: Bool?

    private var isFollowed: Bool { followOverride ?? item.isFollowed }

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.logo, maxPixel: 260, contentMode: .fill, cornerRadius: 12)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if !item.description.isEmpty {
                    Text(FeedHTML.plainText(item.description))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                // 关注列表这类接口不给动态条数，拿不到就不显示，别写“0 条动态”。
                if item.feedNum > 0 {
                    Text("\(formatCount(item.feedNum)) 条动态")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button(isFollowed ? "已关注" : "关注") {
                guard store.requireLogin() else { return }
                let next = !isFollowed
                followOverride = next
                Task {
                    do {
                        try await API.followTopic(tag: item.title, follow: next)
                    } catch {
                        followOverride = item.isFollowed
                        store.present((error as? APIError)?.errorDescription ?? "操作失败")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: width)
        .cardBackground(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture { store.openTopic(item.title) }
    }
}

struct UserCardView: View {
    let user: UserBrief
    let width: CGFloat

    @Environment(AppStore.self) private var store
    @State private var followed = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatar, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.username).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if user.level > 0 {
                        Text("Lv.\(user.level)")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Palette.brandSoft, in: Capsule())
                            .foregroundStyle(Palette.brand)
                    }
                }
                if !user.bio.isEmpty {
                    Text(FeedHTML.plainText(user.bio))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button(followed ? "已关注" : "关注") {
                guard store.requireLogin() else { return }
                followed.toggle()
                Task { try? await API.followUser(uid: user.id, follow: followed) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: width)
        .cardBackground(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture { store.openUser(user.id) }
        .onAppear { followed = user.isFollowed }
    }
}

// MARK: - 分节标题

/// `titleCard` 等分节标题，右侧带「更多」入口。
struct SectionHeaderCard: View {
    let key: String
    let title: String
    let url: String
    let subtitle: String

    @Environment(AppStore.self) private var store
    @State private var hovering = false

    var body: some View {
        Button {
            if !url.isEmpty { store.openTarget(url: url) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.brand)
                    .frame(width: 3, height: 15)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !url.isEmpty {
                    HStack(spacing: 2) {
                        Text("更多")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? Palette.brand : Color.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url.isEmpty)
        .onHover { hovering = $0 }
    }
}

// MARK: - 胶囊链接条

/// `selectorLinkCard` / `sortSelectCard` / `capsuleListCard`：一排可点击的胶囊。
struct LinkBarCard: View {
    let key: String
    let links: [HomeSection]
    let width: CGFloat

    @Environment(AppStore.self) private var store

    @State private var selected: String?

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(links) { link in
                        let active = selected == link.id
                        Button {
                            selected = link.id
                            store.openTarget(url: link.url)
                        } label: {
                            HStack(spacing: 5) {
                                Text(link.title)
                                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                                if !link.subtitle.isEmpty, link.subtitle != link.title {
                                    Text(link.subtitle)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .foregroundStyle(active ? Palette.brand : Color.primary)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.clear.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - 竖版子栏目

/// `verticalColumnsFullPageCard`：话题等页面的子栏目切换。
struct ColumnTabsCard: View {
    let key: String
    let columns: [HomeSection]
    let width: CGFloat

    @Environment(AppStore.self) private var store
    @State private var current: String?

    private var active: HomeSection? {
        if let current, let match = columns.first(where: { $0.id == current }) { return match }
        return columns.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassPillBar(
                items: columns,
                title: \.title,
                isSelected: { $0.id == (active?.id ?? "") },
                onSelect: { current = $0.id }
            )
            if let active, !active.url.isEmpty {
                ColumnPageList(url: active.url)
                    .id(active.id)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// 子栏目对应的动态列表，复用统一的加载模型。
struct ColumnPageList: View {
    let url: String

    @State private var model: FeedListModel?

    var body: some View {
        Group {
            if let model {
                FeedListView(model: model)
                    .frame(height: 520)
            } else {
                LoadingRow()
                    .frame(height: 220)
            }
        }
        .task(id: url) {
            let created = makeModel()
            model = created
        }
    }

    private func makeModel() -> FeedListModel {
        let pageName = ColumnPageList.pageName(from: url)
        if pageName.hasPrefix("/") || pageName.contains("?") {
            return FeedListModel(source: .rawLink(pageName))
        }
        return FeedListModel(source: .page(pageName, nil))
    }

    /// 从 `#/topic/tagList?keywords=热门…` / `/page?url=V11_XXX` 里取出可请求的地址。
    static func pageName(from url: String) -> String {
        var value = url
        if let range = value.range(of: "url=") {
            value = String(value[range.upperBound...])
            if let amp = value.firstIndex(of: "&") { value = String(value[..<amp]) }
        }
        if value.hasPrefix("/page?") { return value }
        if value.hasPrefix("#") { value.removeFirst() }
        return value
    }
}

// MARK: - 提示类卡片

/// `unLoginCard`：未登录引导。
struct LoginPromptCard: View {
    let key: String
    let title: String
    let width: CGFloat

    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(Palette.brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text("登录后即可看到关注的人发布的动态")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("登录") { store.loginSheetPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Palette.brand)
        }
        .padding(14)
        .frame(width: width)
        .glassPanel(cornerRadius: 16)
    }
}

/// `messageCard`：纯说明文字（支持富文本链接）。
struct NoticeCard: View {
    let key: String
    let text: String
    let width: CGFloat

    @Environment(AppStore.self) private var store

    var body: some View {
        RichTextView(
            attributed: FeedHTML.cachedAttributedString(html: text, fontSize: 12.5, color: .secondaryLabelColor),
            isSelectable: true,
            onLink: { store.handle(link: $0) }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .cardBackground(cornerRadius: 14)
    }
}

// MARK: - 酷品 / 直播

/// 横向商品卡片（酷品、京东联盟等）。
struct GoodsScroller: View {
    let key: String
    let items: [PearGoods]
    let width: CGFloat

    @Environment(AppStore.self) private var store
    @State private var hovering: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        if !item.buyURL.isEmpty {
                            NSWorkspace.shared.open(URL(string: item.buyURL)!)
                        } else if !item.detailURL.isEmpty {
                            store.openTarget(url: item.detailURL)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImage(url: item.image, maxPixel: 480, contentMode: .fill, cornerRadius: 12)
                                .frame(width: 168, height: 168)
                                .clipped()
                            Text(item.title)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(height: 32, alignment: .top)
                            if !item.price.isEmpty {
                                Text(item.price)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.like)
                            }
                            HStack(spacing: 4) {
                                Text(item.mall)
                                Text(item.promoTitle)
                            }
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        .frame(width: 168, alignment: .leading)
                        .padding(10)
                        .cardBackground(cornerRadius: 14)
                        .hoverLift(hovering == item.id)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 ? item.id : (hovering == item.id ? nil : hovering) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(width: width, alignment: .leading)
    }
}

/// 直播预告卡片。
struct LiveScroller: View {
    let key: String
    let items: [LiveTopic]
    let width: CGFloat

    @State private var hovering: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    LiveTile(item: item, hovering: hovering == item.id)
                        .onHover { hovering = $0 ? item.id : (hovering == item.id ? nil : hovering) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(width: width, alignment: .leading)
    }
}

private struct LiveTile: View {
    let item: LiveTopic
    let hovering: Bool

    @Environment(AppStore.self) private var store

    var body: some View {
        Button {
            store.openUser(item.presenterUID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                cover
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 236, alignment: .leading)
            .hoverLift(hovering)
        }
        .buttonStyle(.plain)
    }

    private var cover: some View {
        RemoteImage(url: item.cover, maxPixel: 700, contentMode: .fill, cornerRadius: 12)
            .frame(width: 236, height: 133)
            .clipped()
            .overlay(alignment: .bottomLeading) { timeBadge }
    }

    @ViewBuilder
    private var timeBadge: some View {
        if !item.timeText.isEmpty {
            Text(item.timeText)
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(.white)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(8)
        }
    }
}

/// 无图标的纵向链接列表。
struct LinkListCard: View {
    let key: String
    let links: [HomeSection]
    let width: CGFloat

    @Environment(AppStore.self) private var store
    @State private var hovering: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                Button {
                    store.openTarget(url: link.url)
                } label: {
                    HStack(spacing: 10) {
                        Text(link.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !link.subtitle.isEmpty {
                            Text(link.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(hovering == link.id ? Palette.brand.opacity(0.08) : .clear)
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 ? link.id : (hovering == link.id ? nil : hovering) }
                if index < links.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 14)
                }
            }
        }
        .frame(width: width)
        .cardBackground(cornerRadius: 16)
    }
}
