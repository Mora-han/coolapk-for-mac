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
                .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 420, ideal: 700)
        }
        .toolbar {
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
            store.refreshBadge()
            if let id = ProcessInfo.processInfo.environment["COOLAPK_OPEN_FEED"], !id.isEmpty {
                await store.openFeed(id: id)
            }
            if let target = ProcessInfo.processInfo.environment["COOLAPK_OPEN"], !target.isEmpty {
                store.route(debugTarget: target)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var store = store
        return List(selection: $store.selection) {
            Section("酷安") {
                row(.home, icon: "house")
                row(.follow, icon: "person.2")
                row(.ranking, icon: "flame")
            }

            if !store.sidebarSections.isEmpty {
                ForEach(store.sidebarSections) { section in
                    if section.title.contains("首页") { EmptyView() } else {
                        Section(section.title) {
                            ForEach(section.tabs) { tab in
                                row(.tab(tab.pageName, tab.title), icon: icon(for: tab.pageName))
                            }
                        }
                    }
                }
            } else {
                Section("发现") {
                    row(.apps, icon: "square.grid.2x2")
                    row(.games, icon: "gamecontroller")
                }
            }

            Section("我的") {
                row(.me, icon: "person.crop.circle")
                row(.notifications, icon: "bell", badge: store.badge.total)
                row(.favorites, icon: "star")
                row(.history, icon: "clock.arrow.circlepath")
                row(.settings, icon: "gearshape")
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 260)
    }

    private func row(_ item: NavItem, icon: String, badge: Int = 0) -> some View {
        Label {
            HStack {
                Text(title(for: item))
                if badge > 0 {
                    Spacer()
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Palette.like, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: icon)
        }
        .tag(item)
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
                feedColumn(title: "关注", requiresLogin: true)
            case .ranking:
                feedColumn(title: "热榜")
            case let .tab(pageName, title):
                feedColumn(title: title, requiresLogin: pageName == "V9_HOME_TAB_FOLLOW")
                    .id(pageName)
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
                feedColumn(title: title, requiresLogin: name == "V9_HOME_TAB_FOLLOW")
                    .id(name)
            }
        }
    }

    /// Feed based destinations share one model instance so that switching columns
    /// never restarts a download that is already in flight.
    private func feedColumn(title: String, requiresLogin: Bool = false) -> some View {
        Group {
            if let contentModel {
                FeedListView(model: contentModel, requiresLogin: requiresLogin)
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .task(id: store.selection) {
            guard let source = source(for: store.selection) else { return }
            if contentModel?.source != source {
                contentModel = FeedListModel(source: source)
            }
        }
    }

    private func source(for item: NavItem?) -> FeedListModel.Source? {
        switch item {
        case .follow:
            return .page("V9_HOME_TAB_FOLLOW", "circle")
        case .ranking:
            return .page("V9_HOME_TAB_RANKING", nil)
        case let .tab(pageName, _):
            return .page(pageName, pageName == "V9_HOME_TAB_FOLLOW" ? "circle" : nil)
        case let .page(pageName, _):
            return .page(pageName, pageName == "V9_HOME_TAB_FOLLOW" ? "circle" : nil)
        default:
            return nil
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
            store.sidebarSections = sections
        }
    }
}
