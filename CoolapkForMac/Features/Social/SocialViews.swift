import AppKit
import SwiftUI

// MARK: - Shared header

/// Reusable banner used by every secondary destination (collection, publisher, question…).
/// Kept generic on purpose so other screens can drop it in with two closures.
struct SocialHeaderCard<Actions: View>: View {
    let logo: String
    let title: String
    let subtitle: String
    let description: String
    let stats: [(String, String)]
    let onOpenUser: (() -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RemoteImage(url: logo, maxPixel: 320, contentMode: .fill, cornerRadius: 16)
                .frame(width: 72, height: 72)
                .glassPanel(cornerRadius: 16)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .onTapGesture { onOpenUser?() }
                }
                if !stats.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(Array(stats.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: 4) {
                                Text(entry.0).foregroundStyle(.secondary)
                                Text(entry.1).fontWeight(.medium)
                            }
                        }
                    }
                    .font(.system(size: 11.5))
                }
                if !description.isEmpty {
                    Text(FeedHTML.plainText(description))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            actions()
        }
        .padding(16)
        .cardBackground(cornerRadius: 18)
    }
}

/// Follow button shared by topics, publishers, collections and products.
struct FollowButton: View {
    let title: String
    let followingTitle: String
    let isFollowing: Bool
    let action: () -> Void

    @Environment(AppStore.self) private var store
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(isFollowing ? followingTitle : title)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(minWidth: 70)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassPanel(cornerRadius: 12, tint: isFollowing ? nil : Palette.brand, interactive: true)
        .foregroundStyle(isFollowing ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.snappy(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Collection

struct CollectionView: View {
    let id: String

    @Environment(AppStore.self) private var store
    @State private var item: CollectionItem?
    @State private var followed = false
    @State private var model: FeedListModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if let model {
                FeedListView(model: model, emptyMessage: "这个收藏夹还是空的")
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .task(id: id) {
            if model == nil { model = FeedListModel(source: .collectionItems(id)) }
            item = try? await API.collectionDetail(id: id)
            followed = item?.isFollowed ?? false
        }
    }

    private var header: some View {
        SocialHeaderCard(
            logo: item?.logo ?? "",
            title: item?.title.isEmpty == false ? item!.title : "收藏夹",
            subtitle: item.map { "由 \($0.username) 创建" } ?? "",
            description: item?.description ?? "",
            stats: item.map { [("内容", formatCount($0.itemNum)), ("关注", formatCount($0.followNum))] } ?? [],
            onOpenUser: { if let uid = item?.uid { store.openUser(uid) } }
        ) {
            FollowButton(title: "关注收藏夹", followingTitle: "已关注", isFollowing: followed) {
                guard store.requireLogin() else { return }
                followed.toggle()
                Task {
                    do { try await API.followCollection(id: id, follow: followed) }
                    catch { followed.toggle(); store.present("操作失败") }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - 看看号

struct DyhView: View {
    let id: String

    enum Kind: String, CaseIterable, Identifiable {
        case all = "全部"
        case article = "文章"
        case feed = "动态"
        var id: String { rawValue }
        var type: String {
            switch self {
            case .all: return "all"
            case .article: return "article"
            case .feed: return "feed"
            }
        }
    }

    @Environment(AppStore.self) private var store
    @State private var item: DyhItem?
    @State private var followed = false
    @State private var kind: Kind = .all
    @State private var model: FeedListModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if let model {
                FeedListView(model: model, emptyMessage: "还没有发布内容")
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .task(id: id) {
            model = FeedListModel(source: .dyhArticles(id, kind.type))
            item = try? await API.dyhDetail(id: id)
            followed = item?.isFollowed ?? false
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            SocialHeaderCard(
                logo: item?.logo ?? "",
                title: item?.title.isEmpty == false ? item!.title : "看看号",
                subtitle: item.map { "\($0.username) · 看看号" } ?? "",
                description: item?.description ?? "",
                stats: item.map { [("关注", formatCount($0.followNum)), ("获赞", formatCount($0.likeNum))] } ?? [],
                onOpenUser: { if let uid = item?.uid { store.openUser(uid) } }
            ) {
                FollowButton(title: "关注", followingTitle: "已关注", isFollowing: followed) {
                    guard store.requireLogin() else { return }
                    followed.toggle()
                    Task {
                        do { try await API.followDyh(id: id, follow: followed) }
                        catch { followed.toggle(); store.present("操作失败") }
                    }
                }
            }
            Picker("", selection: $kind) {
                ForEach(Kind.allCases) { value in Text(value.rawValue).tag(value) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .onChange(of: kind) { _, newValue in
                model = FeedListModel(source: .dyhArticles(id, newValue.type))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - 问答

struct QuestionView: View {
    let id: String

    enum Sort: String, CaseIterable, Identifiable {
        case `default` = "默认"
        case dateline = "最新"
        var id: String { rawValue }
        var value: String { self == .default ? "default" : "dateline_desc" }
    }

    @Environment(AppStore.self) private var store
    @State private var sort: Sort = .default
    @State private var model: FeedListModel?
    @State private var title = "问答"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.bubble")
                        .foregroundStyle(Palette.brand)
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Spacer()
                }
                Picker("", selection: $sort) {
                    ForEach(Sort.allCases) { value in Text(value.rawValue).tag(value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassPanel(cornerRadius: 18)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            Divider().opacity(0.4).padding(.top, 12)
            if let model {
                FeedListView(model: model, emptyMessage: "还没有回答")
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .task(id: id) {
            model = FeedListModel(source: .questionAnswers(id, sort.value))
            if let feed = try? await API.feedDetail(id: id) {
                title = feed.messageTitle.isEmpty ? FeedHTML.plainText(feed.message) : feed.messageTitle
            }
        }
        .onChange(of: sort) { _, newValue in
            model = FeedListModel(source: .questionAnswers(id, newValue.value))
        }
    }
}

// MARK: - 投票

struct VoteView: View {
    let id: String
    @State private var model: FeedListModel?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal").foregroundStyle(Palette.brand)
                Text("投票讨论").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassPanel(cornerRadius: 18)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            Divider().opacity(0.4).padding(.top, 12)
            if let model {
                FeedListView(model: model, emptyMessage: "还没有人参与讨论")
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .task(id: id) {
            if model == nil { model = FeedListModel(source: .voteComments(id)) }
        }
    }
}

// MARK: - User list

/// Generic "people" list: the like list of a dynamic, a follow list, fans…
struct UserListView: View {
    enum Mode: Hashable {
        case likers(String)
        case following(String)
        case fans(String)
        case likersOfReply

        var title: String {
            switch self {
            case .likers: return "点赞的人"
            case .following: return "关注"
            case .fans: return "粉丝"
            case .likersOfReply: return "点赞的人"
            }
        }
    }

    let mode: Mode
    let title: String

    @Environment(AppStore.self) private var store
    @State private var users: [UserBrief] = []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(users) { user in
                    UserTile(user: user)
                        .task {
                            if user.id == users.last?.id, !finished { await load(reset: false) }
                        }
                }
            }
            .padding(18)
            if loading { LoadingRow().padding(.bottom, 16) }
            if users.isEmpty, !loading, error == nil {
                EmptyStateView(title: "还没有人", systemImage: "person.2")
                    .frame(height: 260)
            }
            if let error, users.isEmpty {
                ErrorBanner(message: error) { Task { await load(reset: true) } }
            }
        }
        .task(id: mode) { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if loading { return }
        if reset {
            users = []
            page = 1
            finished = false
        }
        guard !finished else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded: [UserBrief]
            switch mode {
            case let .likers(feedID):
                loaded = try await API.likeList(feedID: feedID, page: page)
            case let .following(uid):
                loaded = try await API.userList(uid: uid, followers: false, page: page)
            case let .fans(uid):
                loaded = try await API.userList(uid: uid, followers: true, page: page)
            case .likersOfReply:
                loaded = []
            }
            let existing = Set(users.map(\.id))
            users.append(contentsOf: loaded.filter { !existing.contains($0.id) })
            if loaded.isEmpty { finished = true }
            page += 1
            error = nil
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Compact user card with follow control, reused by every people grid.
struct UserTile: View {
    let user: UserBrief

    @Environment(AppStore.self) private var store
    @State private var followed = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(url: user.avatar, size: 40)
                .onTapGesture { store.openUser(user.id) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(user.username)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !user.verifyLabel.isEmpty {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.brand)
                    }
                }
                Text(user.bio.isEmpty ? "\(formatCount(user.fansNum)) 粉丝" : FeedHTML.plainText(user.bio))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                guard store.requireLogin() else { return }
                followed.toggle()
                Task {
                    do { try await API.followUser(uid: user.id, follow: followed) }
                    catch { followed.toggle(); store.present("操作失败") }
                }
            } label: {
                Image(systemName: followed ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .glassPanel(cornerRadius: 12, tint: followed ? nil : Palette.brand, interactive: true)
            .foregroundStyle(followed ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))
        }
        .padding(10)
        .cardBackground(cornerRadius: 14)
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.snappy(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { store.openUser(user.id) }
        .onAppear { followed = user.isFollowed }
    }
}

// MARK: - Sheets shared by the detail screen

/// Reposts and revision history are small read-only lists, so they live in a sheet.
struct FeedListSheet: View {
    enum Kind: Hashable {
        case forwards(String)
        case history(String)
        var title: String {
            switch self {
            case .forwards: return "转发"
            case .history: return "编辑历史"
            }
        }
    }

    let kind: Kind

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model: FeedListModel?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(kind.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.brand)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider().opacity(0.4)
            if let model {
                FeedListView(model: model, emptyMessage: "暂时没有内容")
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
        .task(id: kind) {
            if model == nil {
                switch kind {
                case let .forwards(id): model = FeedListModel(source: .forwards(id))
                case let .history(id): model = FeedListModel(source: .changeHistory(id))
                }
            }
        }
    }
}
