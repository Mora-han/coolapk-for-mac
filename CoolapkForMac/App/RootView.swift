import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var contentModel: FeedListModel?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 360, ideal: 520)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 380, ideal: 620)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    store.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!store.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
                .help("后退 ⌘[")

                Button {
                    store.goForward()
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!store.canGoForward)
                .keyboardShortcut("]", modifiers: .command)
                .help("前进 ⌘]")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showCompose = true
                } label: {
                    Label("发布动态", systemImage: "square.and.pencil")
                }
                .help("发布动态")

                ToolbarGlassButton(systemImage: "bell", help: "消息", badge: store.badge.total) {
                    store.selection = .notifications
                }

                Button {
                    store.selection = .me
                } label: {
                    AvatarView(url: store.avatar, size: 22)
                }
                .buttonStyle(.plain)
                .help(store.isLoggedIn ? store.username : "登录")
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索动态、用户、话题")
        .onSubmit(of: .search) {
            store.searching = true
            store.showSearch = true
        }
        .onChange(of: store.searchText) { _, value in
            if value.isEmpty { store.showSearch = false }
        }
        .sheet(isPresented: $store.loginSheetPresented) { LoginSheet() }
        .sheet(isPresented: $store.showCompose) { ComposeSheet() }
        .overlay {
            if let viewer = store.viewer {
                ImageViewerOverlay(state: viewer) {
                    store.viewer = nil
                }
                .zIndex(2)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassPanel(cornerRadius: 12)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: store.toast)
        .task {
            await loadTabs()
            if let tab = DebugHooks.homeTab { store.homeTab = tab }
            store.refreshBadge()
            if let id = ProcessInfo.processInfo.environment["COOLAPK_OPEN_FEED"], !id.isEmpty {
                await store.openFeed(id: id)
            }
            if let target = ProcessInfo.processInfo.environment["COOLAPK_OPEN"], !target.isEmpty {
                store.route(debugTarget: target)
            }
        }
        .background(WindowTitle(title: store.currentTitle))
    }

    // MARK: - Sidebar

    /// 侧边栏用 AppKit 的 source list 承载：选中态是系统的半透明覆盖层，
    /// 和访达 / App Store 一致（SwiftUI 的 List 只能画强调色实心高亮）。
    private var sidebar: some View {
        SourceListSidebar(sections: sidebarSections, selection: store.selection) { item in
            store.selection = item
        }
        .navigationSplitViewColumnWidth(min: 186, ideal: 202, max: 250)
    }

    private var sidebarSections: [SourceListSidebar<NavItem>.Section] {
        var sections: [SourceListSidebar<NavItem>.Section] = [
            .init(id: "coolapk", title: "酷安", rows: [
                entry(.home, icon: "house"),
                entry(.follow, icon: "person.2"),
                entry(.ranking, icon: "flame"),
            ])
        ]

        if !store.sidebarSections.isEmpty {
            for (index, section) in store.sidebarSections.enumerated() where !section.title.contains("首页") {
                sections.append(.init(id: "tab-\(index)", title: section.title, rows: section.tabs.map { tab in
                    entry(.tab(tab.pageName, tab.title), icon: icon(for: tab.pageName))
                }))
            }
        } else {
            sections.append(.init(id: "discover", title: "发现", rows: [
                entry(.apps, icon: "square.grid.2x2"),
                entry(.games, icon: "gamecontroller"),
            ]))
        }

        sections.append(.init(id: "mine", title: "我的", rows: [
            entry(.me, icon: "person.crop.circle"),
            entry(.notifications, icon: "bell", badge: store.badge.total),
            entry(.favorites, icon: "star"),
            entry(.history, icon: "clock.arrow.circlepath"),
            entry(.settings, icon: "gearshape"),
        ]))

        return sections
    }

    private func entry(_ item: NavItem, icon: String, badge: Int = 0) -> SourceListSidebar<NavItem>.Row {
        .init(id: identifier(for: item), value: item, title: title(for: item), systemImage: icon, badge: badge)
    }

    /// 侧栏条目的稳定标识，用于行复用与去重。
    private func identifier(for item: NavItem) -> String {
        switch item {
        case .home: return "home"
        case .follow: return "follow"
        case .ranking: return "ranking"
        case let .tab(pageName, _): return "tab:\(pageName)"
        case let .discover(id, _): return "discover:\(id)"
        case .apps: return "apps"
        case .games: return "games"
        case .me: return "me"
        case .notifications: return "notifications"
        case .messages: return "messages"
        case .history: return "history"
        case .favorites: return "favorites"
        case .settings: return "settings"
        case let .topic(tag): return "topic:\(tag)"
        case let .user(uid): return "user:\(uid)"
        case let .app(id, _): return "app:\(id)"
        case let .product(id, _): return "product:\(id)"
        case let .collection(id, _): return "collection:\(id)"
        case let .dyh(id, _): return "dyh:\(id)"
        case .dyhList: return "dyh-list"
        case let .question(id, _): return "question:\(id)"
        case let .vote(id, _): return "vote:\(id)"
        case let .page(name, _): return "page:\(name)"
        }
    }

    private func title(for item: NavItem) -> String {
        switch item {
        case .home: return "首页"
        case .follow: return "关注"
        case .ranking: return "热榜"
        case let .tab(_, title): return title
        case let .discover(_, title): return title
        case .apps: return "应用"
        case .games: return "游戏"
        case .me: return "我"
        case .notifications: return "消息"
        case .messages: return "私信"
        case .history: return "浏览历史"
        case .favorites: return "我的收藏"
        case .settings: return "设置"
        case let .topic(tag): return "#\(tag)"
        case let .user(uid): return "用户 \(uid)"
        case let .app(_, title): return title
        case let .product(_, title): return title
        case let .collection(_, title): return title
        case let .dyh(_, title): return title
        case let .dyhList(title): return title
        case let .question(_, title): return title
        case let .vote(_, title): return title
        case let .page(_, title): return title
        }
    }

    private func icon(for pageName: String) -> String {
        switch pageName {
        case "V9_HOME_TAB_FOLLOW": return "person.2"
        case "V9_HOME_TAB_HEADLINE": return "flame"
        case "V9_HOME_TAB_RANKING": return "chart.bar"
        case "V11_HOME_TAB_NEWS": return "bolt"
        case "V11_VERTICAL_TOPIC": return "number"
        case "V9_HOME_TAB_SHIPIN": return "play.rectangle"
        case "V9_HOME_TAB_WENDA": return "questionmark.circle"
        case "V11_HOME_NEW": return "iphone.gen3"
        case "V11_HOME_CAR": return "car"
        case "V11_HOME_TAB_JC": return "book"
        case "V11_HOME_MEIHUA": return "paintpalette"
        case "V13_IOSHOME_OPENSHOW": return "shippingbox"
        case "V13_HOME_SHEYING": return "camera"
        case "V11_DIGITAL_PRODUCT_LIST": return "cube.box"
        case "V10_DIGITAL_HOME": return "cpu"
        case "V10_CHANNEL_SJB": return "iphone"
        case "V10_CHANNEL_SMB_TOP": return "trophy"
        case "V11_FIND_GOODS": return "bag"
        case "V11_DISCOVERY_SECOND_HAND": return "arrow.2.squarepath"
        case "V11_FIND_COOLPIC": return "photo.on.rectangle.angled"
        case "V11_FIND_DYH": return "newspaper"
        case "V12_FIND_KUBANG": return "list.star"
        default: return "square.grid.2x2"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentColumn: some View {
        if store.showSearch {
            SearchView()
        } else {
            switch store.selection {
            case .home, .none:
                HomeTimelineView()
                    .navigationTitle("酷安")
            case .follow:
                feedColumn(title: "关注", route: .feed(name: "V9_HOME_TAB_FOLLOW", type: "circle"), requiresLogin: true)
            case .ranking:
                feedColumn(title: "热榜", route: .feed(name: "V9_HOME_TAB_RANKING", type: nil))
            case let .tab(pageName, title):
                tabContent(pageName: pageName, title: title)
            case let .dyhList(title):
                feedColumn(title: title, route: .dyh)
            case .apps:
                AppsView(type: 1, title: "应用").navigationTitle("应用")
            case .games:
                AppsView(type: 2, title: "游戏").navigationTitle("游戏")
            case .me:
                MeView().navigationTitle("我")
            case .notifications:
                NotificationsView().navigationTitle("消息")
            case .messages:
                MessagesView().navigationTitle("私信")
            case .history:
                HistoryView().navigationTitle("浏览历史")
            case .favorites:
                FavoritesView().navigationTitle("我的收藏")
            case .settings:
                SettingsView().navigationTitle("设置")
            case let .topic(tag):
                TopicView(tag: tag).navigationTitle("#\(tag)")
            case let .user(uid):
                UserView(uid: uid).navigationTitle("用户主页")
            case let .app(id, title):
                AppDetailView(id: id, title: title).navigationTitle(title)
            case let .discover(key, id):
                if key.hasPrefix("product-") {
                    ProductView(id: id).navigationTitle("商品")
                } else {
                    EmptyStateView(title: "暂不支持的内容", systemImage: "questionmark.square.dashed")
                }
            case let .product(id, title):
                ProductView(id: id).navigationTitle(title)
            case let .collection(id, title):
                CollectionView(id: id).navigationTitle(title)
            case let .dyh(id, title):
                DyhView(id: id).navigationTitle(title)
            case let .question(id, title):
                QuestionView(id: id).navigationTitle(title)
            case let .vote(id, title):
                VoteView(id: id).navigationTitle(title)
            case let .page(name, title):
                tabContent(pageName: name, title: title)
            }
        }
    }

    /// 侧栏 / 首页标签的内容列，按 `/v6/main/init` 给的页面地址决定用哪种列表。
    @ViewBuilder
    private func tabContent(pageName: String, title: String) -> some View {
        let route = store.route(forPage: pageName)
        if route == .digitalLibrary {
            DigitalLibraryView().navigationTitle(title)
        } else {
            feedColumn(title: title, route: route, requiresLogin: pageName == "V9_HOME_TAB_FOLLOW")
                .id(pageName)
        }
    }

    /// Feed based destinations share one model instance so that switching columns
    /// never restarts a download that is already in flight.
    private func feedColumn(title: String, route: PageRoute, requiresLogin: Bool = false) -> some View {
        Group {
            if let contentModel {
                FeedListView(model: contentModel, requiresLogin: requiresLogin)
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .task(id: route) {
            guard let source = route.source else { return }
            if contentModel?.source != source {
                contentModel = FeedListModel(source: source)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let feed = store.selectedFeed {
            FeedDetailView(feed: feed)
                .id(feed.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("选择一条动态查看详情")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("双击或点击左侧卡片即可在此阅读全文与评论")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadTabs() async {
        guard store.sidebarSections.isEmpty else { return }
        if let sections = try? await API.tabConfiguration() {
            store.apply(sections: sections)
        }
    }
}
