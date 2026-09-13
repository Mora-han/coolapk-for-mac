import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

// MARK: - App card

struct AppCardView: View {
    let item: AppItem
    let width: CGFloat

    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.logo, maxPixel: 260, contentMode: .fill, cornerRadius: 14)
                .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if !item.score.isEmpty, item.score != "0" {
                        Text(item.score)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Palette.brandSoft, in: Capsule())
                            .foregroundStyle(Palette.brand)
                    }
                    if !item.updateFlag.isEmpty {
                        TagChip(text: "更新", tint: .orange)
                    }
                }
                if !item.description.isEmpty {
                    Text(FeedHTML.plainText(item.description))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if !item.category.isEmpty { Text(item.category) }
                    if !item.size.isEmpty { Text(item.size) }
                    if !item.downloadCount.isEmpty { Text("\(item.downloadCount)次下载") }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button("详情") {
                store.selection = .app(item.id, item.title)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: width)
        .cardBackground(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture { store.selection = .app(item.id, item.title) }
    }
}

// MARK: - App / game list

struct AppsView: View {
    let type: Int
    let title: String

    @Environment(AppStore.self) private var store
    @State private var items: [AppItem] = []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let error, items.isEmpty {
                    ErrorBanner(message: error) { Task { await load(reset: true) } }
                }
                ForEach(items) { item in
                    AppCardView(item: item, width: min(760, store.contentWidth + 140) - 36)
                        .task {
                            if item.id == items.last?.id, !finished { await load(reset: false) }
                        }
                }
                if loading { LoadingRow() }
                if items.isEmpty, !loading, error == nil {
                    EmptyStateView(title: "暂无内容", systemImage: "square.grid.2x2").frame(height: 240)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
        }
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if loading { return }
        if reset {
            items = []
            page = 1
            finished = false
        }
        guard !finished else { return }
        loading = true
        defer { loading = false }
        do {
            let rows = try await API.appIndex(type: type, page: page)
            let apps = rows.compactMap { row -> AppItem? in
                if case let .app(item) = row { return item }
                return nil
            }
            let existing = Set(items.map(\.id))
            items.append(contentsOf: apps.filter { !existing.contains($0.id) })
            if apps.isEmpty { finished = true }
            page += 1
            error = nil
        } catch {
            self.error = LoadError.message(error)
        }
    }
}

// MARK: - App detail

struct AppDetailView: View {
    let id: String
    let title: String

    @Environment(AppStore.self) private var store
    @State private var item: AppItem?
    @State private var error: String?
    @State private var comments: FeedListModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let item, !item.screenshots.isEmpty {
                    screenshots(item.screenshots)
                }
                if let item, !item.changelog.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("更新日志").font(.system(size: 13.5, weight: .semibold))
                        RichTextView(
                            attributed: FeedHTML.cachedAttributedString(html: item.changelog, fontSize: 13, color: .secondaryLabelColor),
                            isSelectable: true
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground(cornerRadius: 16)
                }
                commentsSection
            }
            .frame(maxWidth: min(760, store.contentWidth + 140))
            .frame(maxWidth: .infinity)
            .padding(18)
        }
        .task {
            do {
                item = AppItem(json: try await API.appDetail(id: id))
            } catch {
                self.error = LoadError.message(error)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                RemoteImage(url: item?.logo ?? "", maxPixel: 300, contentMode: .fill, cornerRadius: 16)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item?.title ?? title).font(.system(size: 17, weight: .semibold))
                    if let item {
                        Text("\(item.developer) · \(item.category)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            if !item.score.isEmpty { Label(item.score, systemImage: "star.fill").foregroundStyle(Palette.star) }
                            Label(item.size, systemImage: "internaldrive")
                            Label(item.downloadCount, systemImage: "arrow.down.circle")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let item, !item.description.isEmpty {
                RichTextView(
                    attributed: FeedHTML.cachedAttributedString(html: item.description, fontSize: 13, color: .labelColor),
                    maxLines: 6,
                    isSelectable: true
                )
            }
            HStack(spacing: 10) {
                Button {
                    if let item, let url = URL(string: "https://www.coolapk.com/apk/\(item.packageName)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("在酷安网页版查看", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .padding(18)
        .cardBackground(cornerRadius: 18)
    }

    private func screenshots(_ images: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("截图").font(.system(size: 13.5, weight: .semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                        RemoteImage(url: url, maxPixel: 900, contentMode: .fill, cornerRadius: 12)
                            .frame(width: 190, height: 340)
                            .onTapGesture {
                                store.viewer = ViewerState(images: images, index: index, title: title)
                            }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .cardBackground(cornerRadius: 16)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("评论 \(item?.commentCount ?? 0)").font(.system(size: 13.5, weight: .semibold))
            if let comments, comments.rows.isEmpty, comments.isLoading {
                LoadingRow()
            }
            if let comments {
                ForEach(comments.rows) { row in
                    FeedRowView(row: row, width: min(760, store.contentWidth + 140) - 60, model: comments)
                }
                if comments.rows.isEmpty, !comments.isLoading {
                    Text("暂无评论").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .cardBackground(cornerRadius: 16)
        .task {
            if comments == nil { comments = FeedListModel(source: .appComments(id)) }
            if let comments, comments.isEmpty { await comments.load() }
        }
    }
}

// MARK: - Topic

struct TopicView: View {
    let tag: String

    @Environment(AppStore.self) private var store
    @State private var topic: TopicItem?
    @State private var followed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FeedListView(model: FeedListModel(source: .topic(tag)), emptyMessage: "话题还没有内容")
                .id(tag)
        }
        .task {
            topic = try? await API.topicDetail(tag: tag)
            followed = topic?.isFollowed ?? false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RemoteImage(url: topic?.logo ?? "", maxPixel: 200, contentMode: .fill, cornerRadius: 12)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(topic?.title ?? tag).font(.system(size: 15, weight: .semibold))
                HStack(spacing: 10) {
                    if let topic {
                        Text("\(formatCount(topic.feedNum)) 条动态")
                        Text("\(formatCount(topic.followNum)) 人关注")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(followed ? "已关注" : "关注话题") {
                guard store.requireLogin() else { return }
                followed.toggle()
                Task { try? await API.followTopic(tag: tag, follow: followed) }
            }
            .buttonStyle(.borderedProminent)
            .tint(followed ? Color.secondary.opacity(0.4) : Palette.brand)
            .controlSize(.regular)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Product

struct ProductView: View {
    let id: String

    @Environment(AppStore.self) private var store
    @State private var product: ProductItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FeedListView(model: FeedListModel(source: .page("/page?url=/product/feedList?type=0&id=\(id)", nil)),
                          emptyMessage: "暂无相关动态")
                .id(id)
        }
        .task { product = try? await API.productDetail(id: id) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RemoteImage(url: product?.logo ?? "", maxPixel: 240, contentMode: .fill, cornerRadius: 12)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(product?.title ?? "商品详情").font(.system(size: 15, weight: .semibold))
                if let product, !product.description.isEmpty {
                    Text(FeedHTML.plainText(product.description))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let product, !product.score.isEmpty, product.score != "0" {
                Text(product.score)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.brand)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
