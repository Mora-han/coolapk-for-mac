import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

struct NotificationsView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case comments = "评论"
        case atMe = "@我"
        case atComment = "@评论"
        case likes = "赞"
        case follows = "关注"
        var id: String { rawValue }

        var path: String {
            switch self {
            case .comments: return "list"
            case .atMe: return "atMeList"
            case .atComment: return "atCommentMeList"
            case .likes: return "feedLikeList"
            case .follows: return "contactsFollowList"
            }
        }
    }

    @Environment(AppStore.self) private var store
    @State private var kind: Kind = .comments
    @State private var items: [NotificationItem] = []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $kind) {
                ForEach(Kind.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .onChange(of: kind) { _, _ in
                Task { await load(reset: true) }
            }
            Divider()
            content
        }
        .task { await load(reset: true) }
    }

    @ViewBuilder
    private var content: some View {
        if !store.isLoggedIn {
            EmptyStateView(
                title: "登录后查看消息",
                message: "登录后即可收到评论、@ 和点赞提醒。",
                systemImage: "bell.badge",
                actionTitle: "登录",
                action: { store.loginSheetPresented = true }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let error, items.isEmpty {
                        ErrorBanner(message: error) { Task { await load(reset: true) } }
                    }
                    ForEach(items) { item in
                        NotificationRow(item: item) { target in
                            handle(target)
                        }
                        .task {
                            if item.id == items.last?.id, !finished { await load(reset: false) }
                        }
                    }
                    if loading { LoadingRow() }
                    if items.isEmpty, !loading, error == nil {
                        EmptyStateView(title: "暂时没有新消息", systemImage: "bell")
                            .frame(height: 260)
                    }
                }
                .frame(maxWidth: min(760, store.contentWidth + 140))
                .frame(maxWidth: .infinity)
                .padding(18)
            }
            .refreshable { await load(reset: true) }
        }
    }

    private func handle(_ target: NotificationTarget) {
        switch target {
        case let .feed(id):
            Task { await store.openFeed(id: id) }
        case let .user(uid):
            store.openUser(uid)
        case let .topic(tag):
            store.openTopic(tag)
        case let .web(url):
            NSWorkspace.shared.open(url)
        }
    }

    private func load(reset: Bool) async {
        guard store.isLoggedIn else { return }
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
            let raw = try await API.notifications(type: kind.path, page: page)
            let parsed = raw.map { NotificationItem(json: $0) }
            let existing = Set(items.map(\.id))
            items.append(contentsOf: parsed.filter { !existing.contains($0.id) })
            if parsed.isEmpty { finished = true }
            page += 1
            error = nil
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

enum NotificationTarget {
    case feed(String)
    case user(String)
    case topic(String)
    case web(URL)
}

struct NotificationRow: View {
    let item: NotificationItem
    var onOpen: (NotificationTarget) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: item.avatar, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.username.isEmpty ? item.title : item.username)
                        .font(.system(size: 13, weight: .medium))
                    Text(item.raw.action.string.isEmpty ? item.title : item.raw.action.string)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.datelineText.isEmpty ? relativeTime(item.dateline) : item.datelineText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if !item.message.isEmpty {
                    RichTextView(
                        attributed: FeedHTML.cachedAttributedString(html: item.message, fontSize: 12.5, color: .secondaryLabelColor),
                        maxLines: 3,
                        isSelectable: false,
                        onTap: { open() }
                    )
                }
                if !item.extraTitle.isEmpty {
                    Text(item.extraTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .cardBackground(cornerRadius: 14)
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }

    private func open() {
        let url = item.url
        if url.contains("/feed/"), let id = url.split(separator: "/").last.map(String.init) {
            onOpen(.feed(id.replacingOccurrences(of: "?", with: "")))
        } else if url.contains("/u/"), let uid = url.split(separator: "/").last.map(String.init) {
            onOpen(.user(uid))
        } else if url.contains("/t/") {
            let tag = url.replacingOccurrences(of: "/t/", with: "").split(separator: "?").first.map(String.init) ?? ""
            onOpen(.topic(tag))
        } else if let link = URL(string: url.hasPrefix("http") ? url : "https://www.coolapk.com" + url) {
            onOpen(.web(link))
        }
    }
}

struct MessagesView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [MessageItem] = []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false

    var body: some View {
        Group {
            if !store.isLoggedIn {
                EmptyStateView(title: "登录后查看私信", systemImage: "bubble.left.and.bubble.right",
                               actionTitle: "登录", action: { store.loginSheetPresented = true })
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            HStack(spacing: 12) {
                                AvatarView(url: item.avatar, size: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(item.username).font(.system(size: 13.5, weight: .medium))
                                        Spacer()
                                        Text(relativeTime(item.dateline)).font(.system(size: 11)).foregroundStyle(.tertiary)
                                    }
                                    Text(FeedHTML.plainText(item.message))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if item.unreadNum > 0 {
                                    Text("\(item.unreadNum)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Palette.like, in: Capsule())
                                }
                            }
                            .padding(12)
                            .cardBackground(cornerRadius: 14)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let url = URL(string: "https://www.coolapk.com/message/\(item.uid)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .task {
                                if item.id == items.last?.id, !finished { await load(reset: false) }
                            }
                        }
                        if loading { LoadingRow() }
                        if items.isEmpty, !loading {
                            EmptyStateView(title: "还没有私信", systemImage: "bubble.left").frame(height: 240)
                        }
                    }
                    .frame(maxWidth: min(760, store.contentWidth + 140))
                    .frame(maxWidth: .infinity)
                    .padding(18)
                }
                .refreshable { await load(reset: true) }
            }
        }
        .task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard store.isLoggedIn, !loading else { return }
        if reset {
            items = []
            page = 1
            finished = false
        }
        guard !finished else { return }
        loading = true
        defer { loading = false }
        let list = (try? await API.messages(page: page)) ?? []
        let existing = Set(items.map(\.id))
        items.append(contentsOf: list.filter { !existing.contains($0.id) })
        if list.isEmpty { finished = true }
        page += 1
    }
}

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var kind: Kind = .recent

    enum Kind: String, CaseIterable, Identifiable {
        case recent = "最近浏览"
        case hit = "浏览历史"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if !store.isLoggedIn {
                EmptyStateView(title: "登录后同步浏览历史", systemImage: "clock.arrow.circlepath",
                               actionTitle: "登录", action: { store.loginSheetPresented = true })
            } else {
                VStack(spacing: 0) {
                    Picker("", selection: $kind) {
                        ForEach(Kind.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    FeedListView(model: FeedListModel(source: .history(kind == .hit ? "hit" : "recent")),
                                 emptyMessage: "还没有浏览记录")
                        .id(kind)
                }
            }
        }
    }
}

struct FavoritesView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if !store.isLoggedIn {
            EmptyStateView(title: "登录后查看收藏", systemImage: "star",
                           actionTitle: "登录", action: { store.loginSheetPresented = true })
        } else {
            FeedListView(model: FeedListModel(source: .collection(store.uid)), emptyMessage: "还没有收藏内容")
        }
    }
}
