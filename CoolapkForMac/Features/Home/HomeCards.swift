import AppKit
import SwiftUI

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
                Text("\(formatCount(item.feedNum)) 条动态")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button(item.isFollowed ? "已关注" : "关注") {
                guard store.requireLogin() else { return }
                Task { try? await API.followTopic(tag: item.title, follow: !item.isFollowed) }
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
