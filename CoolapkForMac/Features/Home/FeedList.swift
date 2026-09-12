import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

// MARK: - Loading model

@MainActor
@Observable
final class FeedListModel {
    enum Source: Hashable {
        case home
        case page(String, String?)
        case user(String)
        case topic(String)
        case search(String, String)
        case appComments(String)
        case history(String)
        case collection(String)
        case collectionItems(String)
        case dyhArticles(String, String)
        case questionAnswers(String, String)
        case voteComments(String)
        case device(String)
        case forwards(String)
        case likes(String)
        case changeHistory(String)
        /// 直接以 `/v6/page/dataList` 请求某个页面地址（子栏目、专题等）。
        case rawLink(String)
    }

    let source: Source
    var rows: [HomeFeedRow] = []
    var isLoading = false
    var finished = false
    var error: String?
    var page = 1
    var lastUpdated = Date()

    init(source: Source) { self.source = source }

    var isEmpty: Bool { rows.isEmpty }

    func load(reset: Bool = false) async {
        if isLoading { return }
        if reset {
            page = 1
            finished = false
            error = nil
        }
        guard !finished else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded: [HomeFeedRow]
            switch source {
            case .home:
                loaded = try await API.homeFeed(page: page)
            case let .page(name, type):
                loaded = try await API.pageFeed(pageName: name, page: page, type: type)
            case let .user(uid):
                loaded = try await API.userFeeds(uid: uid, page: page)
            case let .topic(tag):
                loaded = try await API.topicFeeds(tag: tag, page: page)
            case let .search(keyword, type):
                loaded = try await API.rows(from: API.search(keyword: keyword, type: type, page: page))
            case let .appComments(id):
                loaded = try await API.appComments(id: id, page: page)
            case let .history(kind):
                loaded = kind == "hit" ? try await API.hitHistory(page: page) : try await API.recentHistory(page: page)
            case let .collection(uid):
                let items = try await API.collectionList(uid: uid.isEmpty ? nil : uid, page: page)
                loaded = try API.rows(from: items)
            case let .collectionItems(id):
                loaded = try await API.collectionItems(id: id, page: page)
            case let .dyhArticles(id, type):
                loaded = try await API.dyhArticles(id: id, page: page, type: type)
            case let .questionAnswers(id, sort):
                loaded = try await API.questionAnswers(id: id, page: page, sort: sort)
            case let .voteComments(fid):
                loaded = try await API.voteComments(fid: fid, page: page)
            case let .device(tag):
                loaded = try await API.deviceFeeds(tag: tag, page: page)
            case let .forwards(id):
                loaded = try await API.forwardList(feedID: id, page: page)
            case let .likes(uid):
                loaded = try await API.userLikeFeeds(uid: uid, page: page)
            case let .changeHistory(id):
                loaded = try await API.changeHistory(feedID: id)
                finished = true
            case let .rawLink(link):
                loaded = try await API.linkFeed(link: link, page: page)
            }

            if reset { rows = [] }
            let existing = Set(rows.map(\.id))
            rows.append(contentsOf: loaded.filter { !existing.contains($0.id) })
            if loaded.isEmpty { finished = true }
            page += 1
            lastUpdated = Date()
            error = nil
            DebugHooks.log("load \(source) -> \(loaded.count) rows (next page \(page))")
        } catch is CancellationError {
            // 切换页面导致的取消不算错误。
        } catch let apiError as APIError {
            error = apiError.errorDescription
            DebugHooks.log("load \(source) page \(page) failed: \(apiError.errorDescription ?? "")")
        } catch {
            self.error = error.localizedDescription
            DebugHooks.log("load \(source) page \(page) failed: \(error)")
        }
    }

    func loadNextPageIfNeeded(current row: HomeFeedRow) async {
        guard let index = rows.firstIndex(of: row) else { return }
        if index >= rows.count - 3 {
            await load()
        }
    }

    func replace(_ item: FeedItem) {
        guard let index = rows.firstIndex(where: { $0.id == "feed-\(item.id)" }) else { return }
        rows[index] = .feed(item)
    }
}

// MARK: - List

struct FeedListView: View {
    let model: FeedListModel
    var header: AnyView?
    var requiresLogin = false
    var emptyMessage = "这里还没有内容"

    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let header { header }

                    if requiresLogin, !store.isLoggedIn {
                        EmptyStateView(
                            title: "登录后查看关注内容",
                            message: "使用酷安账号登录，即可同步关注、收藏与消息。",
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            actionTitle: "登录",
                            action: { store.loginSheetPresented = true }
                        )
                        .frame(height: 380)
                    } else {
                        content(width: min(proxy.size.width, store.contentWidth) - 32)
                        footer
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.rows.count) { _, _ in
                guard let index = DebugScroll.targetRow else { return }
                guard index < model.rows.count else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    scroller.scrollTo(model.rows[index].id, anchor: .top)
                }
            }
            }
        }
        // 按数据源而不是视图身份触发加载：首页切换 Tab 时视图不会重建。
        .task(id: model.source) { if model.isEmpty { await model.load() } }
        .task(id: store.reloadToken) {
            guard !model.isEmpty else { return }
            await model.load(reset: true)
        }
        .refreshable { await model.load(reset: true) }
        .overlay(alignment: .top) {
            if let error = model.error, model.isEmpty {
                ErrorBanner(message: error) {
                    Task { await model.load(reset: true) }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        if model.isEmpty, !model.isLoading {
            EmptyStateView(title: emptyMessage, systemImage: "text.bubble")
                .frame(height: 320)
        } else {
            ForEach(model.rows) { row in
                FeedRowView(row: row, width: max(320, width), model: model)
                    .task { await model.loadNextPageIfNeeded(current: row) }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoading {
            LoadingRow()
        } else if model.finished, !model.isEmpty {
            Text("没有更多了")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - Row dispatcher

struct FeedRowView: View {
    let row: HomeFeedRow
    let width: CGFloat
    let model: FeedListModel

    @Environment(AppStore.self) private var store

    var body: some View {
        switch row {
        case let .feed(item):
            FeedCardView(item: item, width: width, isSelected: store.selectedFeed?.id == item.id, model: model)
        case let .product(item):
            ProductCardView(item: item, width: width)
        case let .topic(item):
            TopicCardView(item: item, width: width)
        case let .user(item):
            UserCardView(user: item, width: width)
        case let .app(item):
            AppCardView(item: item, width: width)
        case let .banners(key, banners):
            BannerCarousel(key: key, banners: banners, width: width)
        case let .icons(key, links):
            IconLinkGrid(key: key, links: links, width: width)
        case let .sections(key, sections):
            SectionScroller(key: key, sections: sections, width: width)
        case let .text(key, text):
            TextCardView(key: key, text: text, width: width)
        case let .sectionTitle(key, title, url, subtitle):
            SectionHeaderCard(key: key, title: title, url: url, subtitle: subtitle)
        case let .linkBar(key, links):
            LinkBarCard(key: key, links: links, width: width)
        case let .linkList(key, links):
            LinkListCard(key: key, links: links, width: width)
        case let .columnTabs(key, columns):
            ColumnTabsCard(key: key, columns: columns, width: width)
        case let .loginPrompt(key, title):
            LoginPromptCard(key: key, title: title, width: width)
        case let .notice(key, text):
            NoticeCard(key: key, text: text, width: width)
        case let .goods(key, items):
            GoodsScroller(key: key, items: items, width: width)
        case let .lives(key, items):
            LiveScroller(key: key, items: items, width: width)
        }
    }
}

// MARK: - Feed card

struct FeedCardView: View {
    let item: FeedItem
    let width: CGFloat
    var isSelected = false
    var model: FeedListModel?

    @Environment(AppStore.self) private var store
    @State private var expanded = false
    @State private var showShareSheet = false
    @State private var hovering = false

    private var textWidth: CGFloat { max(200, width - 28) }
    private var attributed: NSAttributedString {
        FeedHTML.cachedAttributedString(html: item.message, fontSize: store.fontSize, color: .labelColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if !item.messageTitle.isEmpty {
                Text(item.messageTitle)
                    .font(.system(size: store.fontSize + 2, weight: .semibold))
                    .lineLimit(2)
            }
            if !item.message.isEmpty {
                textBody
            }
            if !item.pics.isEmpty {
                FeedMediaGrid(images: item.pics, width: textWidth, quality: store.usesHighQualityImages ? 2 : 1) { index in
                    store.viewer = ViewerState(images: item.pics, index: index, title: item.username)
                }
            }
            if !item.targetTitle.isEmpty {
                FeedTargetCard(item: item)
            }
            if let source = item.sourceFeed {
                ForwardedCard(item: source)
            }
            actionBar
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .cardBackground(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Palette.brand.opacity(0.65) : .clear, lineWidth: 1.4)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { store.selectedFeed = item }
        .contextMenu { contextMenu }
        .hoverLift(hovering, scale: 1.004)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: item.avatar, size: 38)
                .onTapGesture { store.openUser(item.uid) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.username.isEmpty ? "酷安用户" : item.username)
                        .font(.system(size: 13.5, weight: .semibold))
                        .onTapGesture { store.openUser(item.uid) }
                    if item.isHeadline {
                        TagChip(text: "头条", tint: Palette.like)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    Text(item.datelineText.isEmpty ? relativeTime(item.dateline) : item.datelineText)
                    if store.showsDeviceInfo, !item.deviceTitle.isEmpty {
                        Text("·")
                        Button(item.deviceTitle) { store.searchDevice(item.deviceTitle) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                    }
                    if !item.ipLocation.isEmpty {
                        Text("· IP属地 \(item.ipLocation)")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            RichTextView(
                attributed: attributed,
                maxLines: expanded ? 0 : 6,
                isSelectable: false,
                onLink: { store.handle(link: $0) },
                onTap: { store.selectedFeed = item }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if RichTextMeasure.layout(attributed, width: textWidth, maxLines: 6).truncated || expanded {
                Button(expanded ? "收起" : "展开全文") {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.brand)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 26) {
            Button {
                store.toggleLike(item: item, model: model)
            } label: {
                CountLabel(systemImage: item.isLiked ? "heart.fill" : "heart",
                           count: item.likeNum,
                           active: item.isLiked,
                           activeColor: Palette.like)
            }
            .buttonStyle(.plain)
            .help("点赞")

            Button {
                store.selectedFeed = item
                store.focusReply = true
            } label: {
                CountLabel(systemImage: "bubble.right", count: item.commentNum)
            }
            .buttonStyle(.plain)
            .help("查看评论")

            Button {
                share()
            } label: {
                CountLabel(systemImage: "arrowshape.turn.up.right", count: item.forwardNum + item.shareNum)
            }
            .buttonStyle(.plain)
            .help("分享")

            Button {
                store.toggleCollect(item: item, model: model)
            } label: {
                CountLabel(systemImage: item.isFavorited ? "star.fill" : "star",
                           count: item.favNum,
                           active: item.isFavorited,
                           activeColor: Palette.star)
            }
            .buttonStyle(.plain)
            .help("收藏")

            Spacer()
        }
        .font(.system(size: 12.5))
        .padding(.top, 2)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("查看详情") { store.selectedFeed = item }
        Button("复制正文") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(FeedHTML.plainText(item.message), forType: .string)
        }
        if !item.pics.isEmpty {
            Button("查看图片") { store.viewer = ViewerState(images: item.pics, index: 0, title: item.username) }
        }
        Divider()
        Button("复制链接") { copyLink() }
        Button("在浏览器中打开") {
            if let url = URL(string: "https://www.coolapk.com/feed/\(item.id)") {
                NSWorkspace.shared.open(url)
            }
        }
        Divider()
        Button(item.isLiked ? "取消点赞" : "点赞") { store.toggleLike(item: item, model: model) }
        Button(item.isFavorited ? "取消收藏" : "收藏") { store.toggleCollect(item: item, model: model) }
    }

    private func share() {
        let text = FeedHTML.plainText(item.message)
        let url = URL(string: "https://www.coolapk.com/feed/\(item.id)")!
        let picker = NSSharingServicePicker(items: [text, url])
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://www.coolapk.com/feed/\(item.id)", forType: .string)
        store.present("链接已复制")
    }
}

// MARK: - Media grid

struct FeedMediaGrid: View {
    let images: [String]
    let width: CGFloat
    var quality: Int = 2
    var onOpen: (Int) -> Void

    private let spacing: CGFloat = 6

    var body: some View {
        Group {
            if images.count == 1 {
                single
            } else {
                grid
            }
        }
    }

    private var single: some View {
        AdaptiveRemoteImage(
            url: images[0],
            maxWidth: width,
            maxHeight: min(width * 1.1, 460),
            mode: .crop,
            quality: quality
        ) { onOpen(0) }
    }

    private var columns: Int {
        switch images.count {
        case 2: return 2
        case 4: return 2
        default: return images.count == 3 ? 3 : 3
        }
    }

    private var cellSize: CGFloat {
        let count = CGFloat(columns)
        return (width - spacing * (count - 1)) / count
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                RemoteImage(url: url, maxPixel: 900, contentMode: .fill, cornerRadius: 10, quality: quality)
                    .frame(width: cellSize, height: cellSize)
                    .clipped()
                    .onTapGesture { onOpen(index) }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Target (topic / product / app) card

struct FeedTargetCard: View {
    let item: FeedItem
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            if !item.targetPic.isEmpty {
                RemoteImage(url: item.targetPic, maxPixel: 200, contentMode: .fill, cornerRadius: 9)
                    .frame(width: 38, height: 38)
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Palette.brandSoft)
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: "number").foregroundStyle(Palette.brand))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.targetTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !item.targetInfo.isEmpty {
                    Text(FeedHTML.plainText(item.targetInfo)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if item.targetURL.contains("/t/") || item.kind == .topic {
                store.openTopic(item.targetTitle)
            } else if !item.targetURL.isEmpty {
                store.openTarget(url: item.targetURL)
            }
        }
    }
}

struct ForwardedCard: View {
    let item: ForwardedContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.right").font(.system(size: 11))
                Text(item.username).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            if !item.message.isEmpty {
                RichTextView(
                    attributed: FeedHTML.cachedAttributedString(html: item.message, fontSize: 13.5, color: .secondaryLabelColor),
                    maxLines: 4,
                    isSelectable: false
                )
            }
            if !item.pics.isEmpty {
                FeedMediaGrid(images: Array(item.pics.prefix(3)), width: 240, quality: 1, onOpen: { _ in })
                    .frame(width: 240)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
