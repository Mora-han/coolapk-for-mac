import Foundation
import Observation
import SwiftUI
import CoolapkKit
import LiquidGlassUI

/// Sidebar destinations.
enum NavItem: Hashable, Identifiable {
    case home
    case follow
    case ranking
    case tab(String, String)
    case discover(String, String)
    case apps
    case games
    case me
    case notifications
    case messages
    case history
    case favorites
    case settings
    case topic(String)
    case user(String)
    case app(String, String)
    case product(String, String)
    case collection(String, String)
    case dyh(String, String)
    /// 看看号列表（订阅 / 推荐），入口是列表里的「更多」。
    case dyhList(String)
    case question(String, String)
    case vote(String, String)
    case page(String, String)

    var id: String {
        switch self {
        case .home: return "home"
        case .follow: return "follow"
        case .ranking: return "ranking"
        case let .tab(name, _): return "tab-\(name)"
        case let .discover(name, _): return "discover-\(name)"
        case .apps: return "apps"
        case .games: return "games"
        case .me: return "me"
        case .notifications: return "notifications"
        case .messages: return "messages"
        case .history: return "history"
        case .favorites: return "favorites"
        case .settings: return "settings"
        case let .topic(tag): return "topic-\(tag)"
        case let .user(uid): return "user-\(uid)"
        case let .app(id, _): return "app-\(id)"
        case let .product(id, _): return "product-\(id)"
        case let .collection(id, _): return "collection-\(id)"
        case let .dyh(id, _): return "dyh-\(id)"
        case .dyhList: return "dyh-list"
        case let .question(id, _): return "question-\(id)"
        case let .vote(id, _): return "vote-\(id)"
        case let .page(name, _): return "page-\(name)"
        }
    }
}

@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    // Session
    var uid = ""
    var username = ""
    var avatar = ""
    var isLoggedIn = false {
        didSet { if isLoggedIn != oldValue { refreshBadge() } }
    }
    var badge = NotificationBadge()
    var loginSheetPresented = false

    // Settings
    var showImages = true
    {
        didSet { ImageLoading.showsImages = showImages }
    }
    var usesHighQualityImages = true
    var showsDeviceInfo = true
    var fontSize: Double = 15
    var contentWidth: Double = 620
    var autoPlayGIF = true
    var appearance: Appearance = .system {
        didSet { persist() }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system = "跟随系统"
        case light = "浅色"
        case dark = "深色"
        var id: String { rawValue }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    // Navigation
    var selection: NavItem? = .home {
        didSet {
            guard let value = selection, value != oldValue else { return }
            // 离开搜索页时记下的是搜索页这一帧（而不是它底下的页面），后退才能回到结果列表。
            record(NavFrame(item: oldValue ?? value, search: showSearch))
            showSearch = false
        }
    }

    /// 一帧可回退的界面状态：某个页面，或覆盖在页面上的搜索结果。
    struct NavFrame: Equatable {
        var item: NavItem?
        var search: Bool
    }

    private(set) var history: [NavFrame] = []
    private(set) var future: [NavFrame] = []
    private var suppressHistory = false

    private func record(_ frame: NavFrame) {
        guard !suppressHistory else { return }
        history.append(frame)
        if history.count > 80 { history.removeFirst(history.count - 80) }
        future.removeAll()
    }

    private var currentFrame: NavFrame {
        NavFrame(item: selection, search: showSearch)
    }

    private func apply(_ frame: NavFrame) {
        suppressHistory = true
        selection = frame.item
        showSearch = frame.search
        suppressHistory = false
        // 搜索页靠 @State 存结果，重建后用它重新跑一次上次的关键词。
        if frame.search { searching = !searchText.isEmpty }
    }

    /// 侧栏 / 工具栏的显式跳转：目标就是当前页面时也要离开搜索页，否则点侧栏像没反应。
    func navigate(to item: NavItem) {
        guard item != selection else {
            guard showSearch else { return }
            record(NavFrame(item: item, search: true))
            showSearch = false
            return
        }
        selection = item
    }

    /// 打开搜索页（先记一帧当前页面，⌘[ 可以退回来）。
    func enterSearch() {
        guard !showSearch else { return }
        record(NavFrame(item: selection, search: false))
        showSearch = true
    }

    /// 关闭搜索页（清空搜索框、按 Esc 取消时），并把搜索页记进历史。
    func exitSearch() {
        guard showSearch else { return }
        record(NavFrame(item: selection, search: true))
        suppressHistory = true
        showSearch = false
        suppressHistory = false
    }

    /// 提交搜索：切到搜索页并让它跑一次关键词。
    func submitSearch() {
        enterSearch()
        searching = !searchText.isEmpty
    }
    var selectedFeed: FeedItem?
    var searchText = ""
    var searching = false
    var showCompose = false
    var showSearch = false
    /// 每次自增用于触发当前列表重新加载（⌘R）。
    var reloadToken = false
    /// 首页当前选中的 Tab（page name），提到 AppStore 便于快捷键与状态恢复。
    var homeTab = "V9_HOME_TAB_RECOMMEND"
    var sidebarSections: [SidebarSection] = []
    /// 侧栏 / 首页标签在 `/v6/main/init` 里的页面地址（`url`），路由的权威依据。
    var pageLinks: [String: String] = [:]
    /// 关注页（首页标签与侧栏入口共用）的话题切换状态。
    let follow = FollowTimelineStore()
    var toast: String?
    var viewer: ViewerState?
    var focusReply = false
    var activeTabs: [String: String] = [:]

    private init() {
        ImageLoading.userAgent = CoolapkToken.userAgent
        DebugHooks.installLogSink()
        load()
        ImageLoading.showsImages = showImages
    }

    func load() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "settings.showImages") != nil {
            showImages = defaults.bool(forKey: "settings.showImages")
        }
        if defaults.object(forKey: "settings.highQuality") != nil {
            usesHighQualityImages = defaults.bool(forKey: "settings.highQuality")
        }
        if defaults.object(forKey: "settings.deviceInfo") != nil {
            showsDeviceInfo = defaults.bool(forKey: "settings.deviceInfo")
        }
        let storedFont = defaults.double(forKey: "settings.fontSize")
        if storedFont > 0 { fontSize = storedFont }
        let storedWidth = defaults.double(forKey: "settings.contentWidth")
        if storedWidth > 0 { contentWidth = storedWidth }
        if let raw = defaults.string(forKey: "settings.appearance"),
           let value = Appearance(rawValue: raw) {
            appearance = value
        }

        uid = defaults.string(forKey: "session.uid") ?? ""
        username = defaults.string(forKey: "session.username") ?? ""
        avatar = defaults.string(forKey: "session.avatar") ?? ""
        let token = defaults.string(forKey: "session.token") ?? ""
        let sessid = defaults.string(forKey: "session.sessid") ?? ""
        if !token.isEmpty, !uid.isEmpty {
            isLoggedIn = true
            Task {
                await CoolapkClient.shared.updateLogin(uid: uid, username: username, token: token, sessid: sessid)
            }
        }
    }

    func saveSession(uid: String, username: String, token: String, sessid: String, avatar: String = "") {
        let defaults = UserDefaults.standard
        defaults.set(uid, forKey: "session.uid")
        defaults.set(username, forKey: "session.username")
        defaults.set(token, forKey: "session.token")
        defaults.set(sessid, forKey: "session.sessid")
        defaults.set(avatar, forKey: "session.avatar")
        self.uid = uid
        self.username = username
        self.avatar = avatar
        isLoggedIn = true
        Task {
            await CoolapkClient.shared.updateLogin(uid: uid, username: username, token: token, sessid: sessid)
            await refreshProfile()
        }
    }

    func logout() {
        let defaults = UserDefaults.standard
        for key in ["session.uid", "session.username", "session.token", "session.sessid", "session.avatar"] {
            defaults.removeObject(forKey: key)
        }
        uid = ""
        username = ""
        avatar = ""
        isLoggedIn = false
        follow.reset()
        Task { await CoolapkClient.shared.clearLogin() }
    }

    func refreshProfile() async {
        guard isLoggedIn else { return }
        if let profile = try? await API.myProfile() {
            username = profile.username
            avatar = profile.avatar
            UserDefaults.standard.set(username, forKey: "session.username")
            UserDefaults.standard.set(avatar, forKey: "session.avatar")
        }
    }

    func refreshBadge() {
        guard isLoggedIn else {
            badge = NotificationBadge()
            return
        }
        Task {
            if let value = try? await API.badge() { badge = value }
        }
    }

    func persist() {
        let defaults = UserDefaults.standard
        defaults.set(showImages, forKey: "settings.showImages")
        defaults.set(usesHighQualityImages, forKey: "settings.highQuality")
        defaults.set(showsDeviceInfo, forKey: "settings.deviceInfo")
        defaults.set(fontSize, forKey: "settings.fontSize")
        defaults.set(contentWidth, forKey: "settings.contentWidth")
        defaults.set(appearance.rawValue, forKey: "settings.appearance")
    }

    func present(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toast == message { toast = nil }
        }
    }

    // MARK: - Navigation helpers

    func openUser(_ uid: String) {
        guard !uid.isEmpty else { return }
        selection = .user(uid)
    }

    func openTopic(_ tag: String) {
        guard !tag.isEmpty else { return }
        selection = .topic(tag)
    }

    func searchDevice(_ name: String) {
        searchText = name
        submitSearch()
    }

    /// Routes a link tapped inside a dynamic.
    func handle(link: FeedLink) {
        switch link {
        case let .user(uid): openUser(uid)
        case let .topic(tag): openTopic(tag)
        case let .feed(id): Task { await openFeed(id: id) }
        case let .product(value): openProduct(value)
        case let .app(value): openApp(value)
        case let .collection(value): openCollection(value)
        case let .dyh(value): openDyh(value)
        case let .question(value): openQuestion(value)
        case let .vote(value): openVote(value)
        case let .page(value): openPageQuery(value)
        case let .web(url): NSWorkspace.shared.open(url)
        }
    }

    /// Opens any of the API "url" fields, which may be a path, a full URL or a page name.
    func openTarget(url: String) {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }
        if text.hasPrefix("http"), let parsed = URL(string: text) {
            let query = URLComponents(url: parsed, resolvingAgainstBaseURL: false)?.query ?? ""
            text = parsed.path + (query.isEmpty ? "" : "?\(query)")
        }
        if text.hasPrefix("tab://") { return }
        // 看看号的「更多」是列表页，不是某个看看号，别当成详情 id 打开。
        if text.contains("/dyh/recommendList") || text.contains("/dyhFollowList") {
            let query = URLComponents(string: "https://www.coolapk.com" + (text.hasPrefix("/") ? text : "/" + text))
            let title = query?.queryItems?.first(where: { $0.name == "title" })?.value ?? ""
            openDyhList(title: title)
            return
        }
        if text.contains("/product/") {
            openProduct(text.split(separator: "/").last.map(String.init) ?? "")
        } else if text.contains("/apk/") {
            openApp(text.split(separator: "/").last.map(String.init) ?? "")
        } else if text.contains("/collection/") {
            openCollection(text.split(separator: "/").last.map(String.init) ?? "")
        } else if text.contains("/dyh/") {
            openDyh(text.split(separator: "/").last.map(String.init) ?? "")
        } else if text.contains("/question/") {
            openQuestion(text.split(separator: "/").last.map(String.init) ?? "")
        } else if text.contains("/vote/") {
            openVote(text.split(separator: "/").last.map(String.init) ?? "")
        } else if text.contains("/feed/") {
            let id = text.split(separator: "/").last.map(String.init) ?? ""
            Task { await openFeed(id: id.hasPrefix("#") ? String(id.dropFirst()) : id) }
        } else if text.hasPrefix("/t/") || text.hasPrefix("/tag/") {
            let tag = text.replacingOccurrences(of: "/t/", with: "").replacingOccurrences(of: "/tag/", with: "")
            openTopic(tag.split(separator: "?").first.map(String.init) ?? tag)
        } else if text.hasPrefix("/page") {
            openPageQuery(text)
        } else if text.hasPrefix("/u/") {
            openUser(text.replacingOccurrences(of: "/u/", with: "").split(separator: "?").first.map(String.init) ?? "")
        } else if let link = URL(string: text.hasPrefix("http") ? text : "https://www.coolapk.com" + text) {
            NSWorkspace.shared.open(link)
        }
    }

    func openProduct(_ value: String) {
        let id = value.split(separator: "?").first.map(String.init) ?? value
        guard !id.isEmpty else { return }
        selection = .product(id, "商品详情")
    }

    func openApp(_ value: String) {
        let id = value.split(separator: "?").first.map(String.init) ?? value
        guard !id.isEmpty else { return }
        selection = .app(id, id.contains(".") ? "应用详情" : "应用详情")
    }

    func openCollection(_ value: String) {
        let id = value.split(separator: "?").first.map(String.init) ?? value
        guard !id.isEmpty else { return }
        selection = .collection(id, "收藏夹")
    }

    func openDyh(_ value: String) {
        let id = value.split(separator: "?").first.map(String.init) ?? value
        guard !id.isEmpty else { return }
        selection = .dyh(id, "看看号")
    }

    /// 看看号列表页（`/dyh/recommendList`、`/user/dyhFollowList`）。
    func openDyhList(title: String) {
        selection = .dyhList(title.isEmpty ? "看看号" : title)
    }

    /// 「我关注的话题」完整列表（关注页「更多话题」入口）。
    func openFollowedTopics() {
        guard !uid.isEmpty else { return }
        selection = .page("/UserHelper/getFollowRows?uid=\(uid)&type=topic", "我关注的话题")
    }

    func openQuestion(_ value: String) {
        let id = value.split(separator: "?").first.map(String.init) ?? value
        guard !id.isEmpty else { return }
        selection = .question(id, "问答")
    }

    func openVote(_ value: String) {
        let id = value.split(separator: "?").first.map(String.init) ?? value
        guard !id.isEmpty else { return }
        selection = .vote(id, "投票")
    }

    /// Handles `/page?url=...` style links, which nest another page name or path.
    func openPageQuery(_ value: String) {
        var text = value
        if text.hasPrefix("/page") {
            text = text.replacingOccurrences(of: "/page?", with: "")
        }
        if let range = text.range(of: "url=") {
            let nested = String(text[range.upperBound...])
            let decoded = nested.removingPercentEncoding ?? nested
            if decoded.hasPrefix("/") || decoded.contains("://") {
                openTarget(url: decoded)
            } else {
                let name = decoded.split(separator: "?").first.map(String.init) ?? decoded
                selection = .page(name, pageTitle(for: name))
            }
        }
    }

    func pageTitle(for pageName: String) -> String {
        for section in sidebarSections {
            for tab in section.tabs where tab.pageName == pageName { return tab.title }
        }
        return "酷安"
    }

    /// 一个标签要怎么取数据，只看它自己的页面地址。
    func route(forPage pageName: String) -> PageRoute {
        PageRoute.resolve(link: pageLinks[pageName] ?? "", pageName: pageName)
    }

    /// 不放进侧栏的入口：这几个页面的接口已经不返回内容，留着只会是空白页。
    private static let hiddenPages: Set<String> = [
        "V11_FIND_GOODS",           // 酷品
        "V11_DISCOVERY_SECOND_HAND", // 二手
        "V12_FIND_KUBANG",          // 好物榜
    ]

    /// 整组不放进侧栏的分组：数码那一组是商品 / 导购页面，实际用不上。
    private static let hiddenSectionTitles: Set<String> = [
        "数码",
    ]

    /// 应用侧栏配置：丢掉不展示的入口，并记住每个标签的页面地址（路由与「更多」入口都靠它）。
    func apply(sections: [SidebarSection]) {
        var visible: [SidebarSection] = []
        for section in sections {
            guard !Self.hiddenSectionTitles.contains(where: { section.title.contains($0) }) else { continue }
            let tabs = section.tabs.filter { !Self.hiddenPages.contains($0.pageName) }
            guard !tabs.isEmpty else { continue }
            visible.append(SidebarSection(id: section.id, title: section.title, tabs: tabs))
        }
        sidebarSections = visible
        for section in visible {
            for tab in section.tabs { pageLinks[tab.pageName] = tab.link }
        }
    }

    func openFeed(id: String) async {
        do {
            let item = try await API.feedDetail(id: id)
            guard !item.id.isEmpty else {
                present("这条动态暂时打不开")
                return
            }
            selectedFeed = item
        } catch {
            present((error as? APIError)?.errorDescription ?? "动态加载失败")
        }
    }

    // MARK: - Browsing history

    var canGoBack: Bool { !history.isEmpty }
    var canGoForward: Bool { !future.isEmpty }

    func goBack() {
        guard let previous = history.popLast() else { return }
        future.append(currentFrame)
        apply(previous)
    }

    func goForward() {
        guard let next = future.popLast() else { return }
        history.append(currentFrame)
        if history.count > 80 { history.removeFirst(history.count - 80) }
        apply(next)
    }

    /// 当前页面标题，用于窗口标题与工具栏。
    var currentTitle: String {
        guard let selection else { return "酷安" }
        switch selection {
        case .home: return "酷安"
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
        case let .topic(tag): return "#\(tag)#"
        case .user: return "用户主页"
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

    /// Handles the `COOLAPK_OPEN` environment variable, e.g. `dyh:1480`, `topic:小米`,
    /// `page:V9_HOME_TAB_RANKING`. Useful for automated screenshots and deep links.
    func route(debugTarget: String) {
        let parts = debugTarget.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let value = parts[1]
        switch parts[0] {
        case "feed": Task { await openFeed(id: value) }
        case "user": openUser(value)
        case "topic": openTopic(value)
        case "product": openProduct(value)
        case "app": openApp(value)
        case "collection": openCollection(value)
        case "dyh": openDyh(value)
        case "question": openQuestion(value)
        case "vote": openVote(value)
        case "page": selection = .page(value, pageTitle(for: value))
        case "path": openTarget(url: value)
        case "nav": selection = builtinSection(named: value)
        case "search":
            searchText = value
            submitSearch()
        default: break
        }
    }

    /// 侧边栏内置页面，供调试入口与链接解析共用。
    func builtinSection(named name: String) -> NavItem {
        switch name {
        case "me", "我": return .me
        case "settings", "设置": return .settings
        case "notifications", "消息": return .notifications
        case "messages", "私信": return .messages
        case "history", "浏览历史": return .history
        case "favorites", "我的收藏": return .favorites
        case "apps", "应用": return .apps
        case "games", "游戏": return .games
        case "follow", "关注": return .follow
        case "ranking", "热榜": return .ranking
        case "home", "首页": return .home
        default: return .page(name, pageTitle(for: name))
        }
    }

    // MARK: - Interactions

    func requireLogin() -> Bool {
        if isLoggedIn { return true }
        loginSheetPresented = true
        return false
    }

    func toggleLike(item: FeedItem, model: FeedListModel?) {
        guard requireLogin() else { return }
        var updated = item
        updated.isLiked.toggle()
        updated.likeNum += updated.isLiked ? 1 : -1
        model?.replace(updated)
        if selectedFeed?.id == updated.id { selectedFeed = updated }
        Task {
            do {
                try await API.likeFeed(id: item.id, liked: updated.isLiked, feedType: item.raw.feedType.string)
            } catch {
                model?.replace(item)
                if selectedFeed?.id == item.id { selectedFeed = item }
                present((error as? APIError)?.errorDescription ?? "操作失败")
            }
        }
    }

    func toggleCollect(item: FeedItem, model: FeedListModel?) {
        guard requireLogin() else { return }
        var updated = item
        updated.isFavorited.toggle()
        updated.favNum += updated.isFavorited ? 1 : -1
        model?.replace(updated)
        if selectedFeed?.id == updated.id { selectedFeed = updated }
        Task {
            do {
                try await API.collectFeed(id: item.id, collected: updated.isFavorited)
                present(updated.isFavorited ? "已收藏" : "已取消收藏")
            } catch {
                model?.replace(item)
                if selectedFeed?.id == item.id { selectedFeed = item }
                present((error as? APIError)?.errorDescription ?? "操作失败")
            }
        }
    }

    func toggleFollow(user: UserProfile, completion: @escaping (UserProfile) -> Void) {
        guard requireLogin() else { return }
        var updated = user
        updated.isFollowed.toggle()
        completion(updated)
        Task {
            do {
                try await API.followUser(uid: user.id, follow: updated.isFollowed)
            } catch {
                completion(user)
                present((error as? APIError)?.errorDescription ?? "操作失败")
            }
        }
    }

    func reply(feedID: String, message: String, replyID: String?) async throws {
        _ = try await API.postReply(targetID: replyID ?? feedID, message: message, isReply: replyID != nil)
    }
}

/// 一个侧栏 / 首页标签的取数方式，由 `/v6/main/init` 给的页面地址（`url`）决定。
///
/// 配置里只有信息流页会写成 `/page?url=<页面名>`，其余几项是服务端自带的路由页
/// （`/main/headline`、`/user/dyhSubscribe`）。
/// 以前一律把 `page_name` 当页面名塞进 `dataList`，这些路由页就会永远返回空数组。
enum PageRoute: Equatable {
    case feed(name: String, type: String?)
    case headline
    case dyh

    static func resolve(link: String, pageName: String) -> PageRoute {
        switch API.pageTarget(from: link) {
        case "/main/headline":
            return .headline
        case "/user/dyhSubscribe":
            return .dyh
        case let target where !target.isEmpty && !target.hasPrefix("/"):
            return .feed(name: target, type: target == "V9_HOME_TAB_FOLLOW" ? "circle" : nil)
        case "":
            // 接口还没回来（兜底标签）时按页面名判断。
            return .feed(name: pageName, type: pageName == "V9_HOME_TAB_FOLLOW" ? "circle" : nil)
        default:
            // 还没适配的路由页：退回按页面名取，至少与以前的页面名列表一致。
            return .feed(name: pageName, type: nil)
        }
    }

    /// 转成列表模型的数据源。
    var source: FeedListModel.Source {
        switch self {
        case let .feed(name, type): return .page(name, type)
        case .headline: return .headline
        case .dyh: return .dyhSubscribe
        }
    }
}
