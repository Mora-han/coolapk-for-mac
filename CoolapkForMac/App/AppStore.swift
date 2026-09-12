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
    var selection: NavItem? = .home
    var selectedFeed: FeedItem?
    var searchText = ""
    var searching = false
    var showCompose = false
    var showSearch = false
    var sidebarSections: [SidebarSection] = []
    var toast: String?
    var viewer: ViewerState?
    var focusReply = false
    var activeTabs: [String: String] = [:]

    private init() {
        ImageLoading.userAgent = CoolapkToken.userAgent
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
        searching = true
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

    func openFeed(id: String) async {
        if let item = try? await API.feedDetail(id: id) {
            selectedFeed = item
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
        default: break
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
