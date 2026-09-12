import AppKit
import SwiftUI

struct UserView: View {
    let uid: String
    var showsBackButton = false

    enum Tab: String, CaseIterable, Identifiable {
        case feeds = "动态"
        case follows = "关注"
        case fans = "粉丝"
        case collections = "收藏"
        var id: String { rawValue }
    }

    @Environment(AppStore.self) private var store
    @State private var profile: UserProfile?
    @State private var tab: Tab = .feeds
    @State private var feedModel: FeedListModel?
    @State private var users: [UserBrief] = []
    @State private var loadingUsers = false
    @State private var userPage = 1
    @State private var finishedUsers = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                picker
                content
            }
            .frame(maxWidth: min(760, store.contentWidth + 140))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .task(id: uid) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cover = profile?.cover, !cover.isEmpty {
                        RemoteImage(url: cover, maxPixel: 1_200, contentMode: .fill, cornerRadius: 14)
                    } else {
                        LinearGradient(colors: [Palette.brand.opacity(0.5), Palette.brand.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(height: 132)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
            }
            .frame(height: 132)

            HStack(alignment: .top, spacing: 14) {
                AvatarView(url: profile?.avatar ?? "", size: 74)
                    .offset(y: -46)
                    .padding(.bottom, -46)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(profile?.username ?? "加载中…")
                            .font(.system(size: 17, weight: .semibold))
                        if let verify = profile?.verifyLabel, !verify.isEmpty {
                            TagChip(text: verify, systemImage: "checkmark.seal.fill", tint: Palette.brand)
                        }
                    }
                    if let profile {
                        if profile.level > 0 {
                            LevelBar(level: profile.level, experience: profile.experience, next: profile.nextLevelExperience)
                        }
                        if !profile.bio.isEmpty {
                            Text(FeedHTML.plainText(profile.bio))
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, 4)

            if let profile {
                HStack(spacing: 22) {
                    stat("动态", profile.feedNum) { tab = .feeds }
                    stat("关注", profile.followNum) { tab = .follows }
                    stat("粉丝", profile.fansNum) { tab = .fans }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .cardBackground(cornerRadius: 18)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let profile {
                Button {
                    store.toggleFollow(user: profile) { updated in
                        self.profile = updated
                    }
                } label: {
                    Text(profile.isFollowed ? "已关注" : "关注")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 62)
                }
                .buttonStyle(.borderedProminent)
                .tint(profile.isFollowed ? Color.secondary.opacity(0.4) : Palette.brand)
                .controlSize(.regular)

                Button {
                    if let url = URL(string: "https://www.coolapk.com/u/\(uid)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("私信").font(.system(size: 12.5)).frame(width: 48)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private func stat(_ title: String, _ value: Int, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 1) {
                Text("\(value)").font(.system(size: 13.5, weight: .semibold))
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var picker: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: tab) { _, _ in
            Task { await loadUsers(reset: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .feeds:
            if let feedModel {
                FeedListView(model: feedModel, emptyMessage: "还没有发布动态")
            } else {
                LoadingRow()
            }
        case .follows, .fans:
            userList
        case .collections:
            if store.uid == uid {
                FeedListView(model: FeedListModel(source: .collection(uid)), emptyMessage: "还没有收藏内容")
            } else {
                EmptyStateView(title: "仅本人可见", systemImage: "lock")
                    .frame(height: 200)
            }
        }
    }

    private var userList: some View {
        LazyVStack(spacing: 8) {
            ForEach(users) { user in
                HStack(spacing: 12) {
                    AvatarView(url: user.avatar, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(user.username).font(.system(size: 13.5, weight: .medium))
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
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .cardBackground(cornerRadius: 14)
                .contentShape(Rectangle())
                .onTapGesture { store.openUser(user.id) }
                .task {
                    if user.id == users.last?.id, !finishedUsers { await loadUsers(reset: false) }
                }
            }
            if loadingUsers { LoadingRow() }
            if users.isEmpty, !loadingUsers {
                EmptyStateView(title: tab == .follows ? "还没有关注的人" : "还没有粉丝", systemImage: "person.2")
                    .frame(height: 200)
            }
        }
    }

    private func load() async {
        if feedModel == nil || feedModel?.source != .user(uid) {
            feedModel = FeedListModel(source: .user(uid))
        }
        do {
            profile = try await API.userProfile(uid: uid)
            error = nil
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadUsers(reset: Bool) async {
        guard tab == .follows || tab == .fans else { return }
        if loadingUsers { return }
        if reset {
            users = []
            userPage = 1
            finishedUsers = false
        }
        guard !finishedUsers else { return }
        loadingUsers = true
        defer { loadingUsers = false }
        let list = (try? await API.userList(uid: uid, followers: tab == .fans, page: userPage)) ?? []
        let existing = Set(users.map(\.id))
        users.append(contentsOf: list.filter { !existing.contains($0.id) })
        if list.isEmpty { finishedUsers = true }
        userPage += 1
    }
}

struct LevelBar: View {
    let level: Int
    let experience: Int
    let next: Int

    private var progress: Double {
        guard next > 0, experience > 0 else { return 0 }
        return min(1, Double(experience) / Double(max(next, 1)))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Lv.\(level)")
                .font(.system(size: 10.5, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Palette.brand, in: Capsule())
                .foregroundStyle(.white)
            if next > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Palette.brand.opacity(0.75))
                            .frame(width: max(3, proxy.size.width * progress))
                    }
                }
                .frame(width: 74, height: 5)
            }
        }
    }
}

/// "我" tab: shortcuts plus the signed in profile.
struct MeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.isLoggedIn {
            ScrollView {
                VStack(spacing: 14) {
                    quickLinks
                    UserView(uid: store.uid)
                }
                .padding(.top, 12)
            }
        } else {
            EmptyStateView(
                title: "还没有登录",
                message: "登录酷安账号后可以查看关注、收藏、消息，并参与互动。",
                systemImage: "person.crop.circle.badge.questionmark",
                actionTitle: "登录酷安账号",
                action: { store.loginSheetPresented = true }
            )
        }
    }

    private var quickLinks: some View {
        HStack(spacing: 10) {
            quick("我的收藏", "star", Palette.star) { store.selection = .favorites }
            quick("浏览历史", "clock.arrow.circlepath", .blue) { store.selection = .history }
            quick("我的消息", "bell", .orange) { store.selection = .notifications }
            quick("设置", "gearshape", .gray) { store.selection = .settings }
        }
        .frame(maxWidth: min(760, store.contentWidth + 140))
        .padding(.horizontal, 18)
    }

    private func quick(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 11.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .cardBackground(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}
