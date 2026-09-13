import SwiftUI
import CoolapkKit
import LiquidGlassUI

/// 关注页顶部可切换的内容来源。
enum FollowPill: Hashable, Identifiable {
    /// 关注的人 + 关注的话题合并成的时间线。
    case all
    /// 只有我关注的酷友。
    case users
    /// 某一个关注的话题。
    case topic(String)
    /// 「更多话题」：不在本页切流，点了去完整的话题列表。
    case moreTopics

    var id: String {
        switch self {
        case .all: return "all"
        case .users: return "users"
        case let .topic(tag): return "topic-\(tag)"
        case .moreTopics: return "more-topics"
        }
    }
}

/// 关注页的状态：关注的话题列表 + 每个来源各自的列表模型。
///
/// 模型放在这里（挂在 `AppStore` 上）而不是视图自己的 `@State`，
/// 这样在首页标签之间来回切、或在侧栏与首页两个关注入口之间切，已加载的列表都还在。
@MainActor
@Observable
final class FollowTimelineStore {
    /// 关注页最多取几页话题；关注了几百个话题时不至于打太多请求。
    private static let maxTopicPages = 5

    var topics: [TopicItem] = []
    var selection: FollowPill = .all
    private(set) var model: FeedListModel?
    private(set) var hasMoreTopics = false

    private var models: [String: FeedListModel] = [:]
    private var loadedTopics = false
    private var loadingTopics = false

    var pills: [FollowPill] {
        var list: [FollowPill] = [.all, .users]
        list.append(contentsOf: topics.map { .topic($0.title) })
        if hasMoreTopics { list.append(.moreTopics) }
        return list
    }

    func title(for pill: FollowPill) -> String {
        switch pill {
        case .all: return "所有内容"
        case .users: return "关注用户"
        case let .topic(tag): return "#\(tag)"
        case .moreTopics: return "更多话题"
        }
    }

    func emptyMessage(for pill: FollowPill) -> String {
        switch pill {
        case .all: return "关注的人和话题都还没有新内容"
        case .users: return "关注的酷友还没有新动态"
        case let .topic(tag): return "#\(tag) 还没有新内容"
        case .moreTopics: return ""
        }
    }

    /// 某个来源对应的取数方式。
    func source(for pill: FollowPill) -> FeedListModel.Source {
        switch pill {
        case .all, .moreTopics: return .followAll
        case .users: return .page(API.followPageName, "circle")
        case let .topic(tag): return .topic(tag)
        }
    }

    /// 让当前选中来源的模型就绪，没有就建一个（同一个来源只建一次）。
    func activate() {
        if let existing = models[selection.id] {
            model = existing
            return
        }
        let created = FeedListModel(source: source(for: selection))
        models[selection.id] = created
        model = created
    }

    func select(_ pill: FollowPill) {
        guard pill != .moreTopics else { return }
        selection = pill
        activate()
    }

    /// 当前选中的话题取不到了（取关 / 换账号）时退回「所有内容」。
    private func dropMissingTopics() {
        guard case let .topic(tag) = selection, !topics.contains(where: { $0.title == tag }) else { return }
        selection = .all
        activate()
    }

    /// 首次进入关注页时取一次关注的话题。
    func loadTopicsIfNeeded() async {
        guard !loadedTopics, !loadingTopics else { return }
        loadingTopics = true
        defer { loadingTopics = false }

        var collected: [TopicItem] = []
        var seen = Set<String>()
        var more = false
        for page in 1...Self.maxTopicPages {
            // 取不到就保持原样（下次进页面再试），不要把一个空列表盖上去。
            guard let items = try? await API.followedTopics(page: page) else { break }
            for item in items where seen.insert(item.id).inserted { collected.append(item) }
            guard items.count >= 20 else { more = false; break }
            more = page == Self.maxTopicPages
        }

        guard !collected.isEmpty else { return }
        loadedTopics = true
        hasMoreTopics = more
        topics = collected
        DebugHooks.log("follow topics -> \(collected.count) (more \(more))")
        dropMissingTopics()
    }

    /// 重新取关注话题（登录状态变化、手动刷新时用）。
    func reloadTopics() async {
        loadedTopics = false
        await loadTopicsIfNeeded()
        dropMissingTopics()
    }

    /// 退出登录：清掉话题与各来源的列表。
    func reset() {
        topics = []
        hasMoreTopics = false
        loadedTopics = false
        models = [:]
        selection = .all
        model = nil
        activate()
    }
}

/// 关注页：顶部一条「所有内容 / 关注用户 / 关注的话题」切换，下面是切换后的信息流。
struct FollowTimelineView: View {
    @Environment(AppStore.self) private var store

    private var follow: FollowTimelineStore { store.follow }

    var body: some View {
        VStack(spacing: 0) {
            GlassPillBar(
                items: follow.pills,
                title: { follow.title(for: $0) },
                isSelected: { $0 == follow.selection },
                scrollsToSelection: true,
                onSelect: { pill in
                    if pill == .moreTopics {
                        store.openFollowedTopics()
                    } else {
                        follow.select(pill)
                    }
                }
            )
            Divider().opacity(0.4)

            if let model = follow.model {
                FeedListView(
                    model: model,
                    requiresLogin: true,
                    emptyMessage: follow.emptyMessage(for: follow.selection)
                )
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .onAppear { follow.activate() }
        // 换了账号（或退出登录）时话题要跟着换。
        .onChange(of: store.isLoggedIn) { _, loggedIn in
            guard loggedIn else { follow.reset(); return }
            Task { await follow.reloadTopics() }
        }
        .onChange(of: store.reloadToken) { _, _ in
            Task { await follow.reloadTopics() }
        }
        .task {
            follow.activate()
            await follow.loadTopicsIfNeeded()
            if let target = DebugHooks.followPill {
                // 「更多话题」是跳转不是切流，调试入口也照这个走。
                if target == .moreTopics { store.openFollowedTopics() } else { follow.select(target) }
            }
        }
    }
}
