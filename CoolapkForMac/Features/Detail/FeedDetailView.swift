import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

/// Full dynamic view with the complete text, media, stats and the comment section.
struct FeedDetailView: View {
    let initial: FeedItem

    @Environment(AppStore.self) private var store
    @State private var item: FeedItem
    @State private var replies: [ReplyItem] = []
    @State private var hotReplies: [ReplyItem] = []
    @State private var replyPage = 1
    @State private var finishedReplies = false
    @State private var loadingReplies = false
    @State private var replyMode: ReplyMode = .hot
    @State private var replyText = ""
    @State private var sending = false
    @State private var replyTarget: ReplyItem?
    @State private var sheet: DetailSheet?
    @State private var forwarding = false
    @State private var forwardText = ""

    enum DetailSheet: Identifiable {
        case likers
        case forwards
        case history
        var id: String {
            switch self {
            case .likers: return "likers"
            case .forwards: return "forwards"
            case .history: return "history"
            }
        }
    }

    enum ReplyMode: String, CaseIterable, Identifiable {
        case hot = "热门回复"
        case latest = "最新回复"
        var id: String { rawValue }
    }

    init(feed: FeedItem) {
        initial = feed
        _item = State(initialValue: feed)
    }

    var body: some View {
        ScrollViewReader { scroller in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                main
                replySection.id("replies")
            }
            .frame(maxWidth: min(760, store.contentWidth + 140))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .safeAreaInset(edge: .bottom) { composer }
        .onChange(of: replies.count) { _, _ in
            guard DebugScroll.scrollsToReplies else { return }
            withAnimation(.easeInOut(duration: 0.25)) { scroller.scrollTo("replies", anchor: .top) }
        }
        }
        .task {
            await loadDetail()
            await loadReplies(reset: true)
        }
        .onChange(of: store.focusReply) { _, newValue in
            if newValue { store.focusReply = false }
        }
        .sheet(item: $sheet) { value in
            switch value {
            case .likers:
                UserListView(mode: .likers(item.id), title: "点赞的人")
                    .frame(minWidth: 640, minHeight: 520)
            case .forwards:
                FeedListSheet(kind: .forwards(item.id))
            case .history:
                FeedListSheet(kind: .history(item.id))
            }
        }
        .sheet(isPresented: $forwarding) { forwardSheet }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow
            if !item.messageTitle.isEmpty {
                Text(item.messageTitle)
                    .font(.system(size: store.fontSize + 4, weight: .semibold))
                    .textSelection(.enabled)
            }
            RichTextView(
                attributed: FeedHTML.cachedAttributedString(html: item.message, fontSize: store.fontSize, color: .labelColor),
                isSelectable: true,
                onLink: { store.handle(link: $0) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if !item.pics.isEmpty {
                detailMedia
            }
            if !item.targetTitle.isEmpty { FeedTargetCard(item: item) }
            if let source = item.sourceFeed { ForwardedCard(item: source) }

            Divider().padding(.vertical, 2)
            statsRow
            quickLinks
        }
        .padding(18)
        .cardBackground(cornerRadius: 18)
    }

    /// 详情页的图片：单图按原比例完整展示，多图用网格。
    @ViewBuilder
    private var detailMedia: some View {
        if item.pics.count == 1 {
            AdaptiveRemoteImage(
                url: item.pics[0],
                maxWidth: min(620, store.contentWidth),
                maxHeight: 620,
                mode: .crop,
                quality: 2
            ) {
                store.viewer = ViewerState(images: item.pics, index: 0, title: item.username)
            }
        } else {
            FeedMediaGrid(images: item.pics, width: min(620, store.contentWidth), quality: 2) { index in
                store.viewer = ViewerState(images: item.pics, index: index, title: item.username)
            }
        }
    }

    private var authorRow: some View {
        HStack(spacing: 10) {
            AvatarView(url: item.avatar, size: 42)
                .onTapGesture { store.openUser(item.uid) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.username).font(.system(size: 14, weight: .semibold))
                        .onTapGesture { store.openUser(item.uid) }
                    if item.isHeadline { TagChip(text: "头条", tint: Palette.like) }
                }
                HStack(spacing: 5) {
                    Text(item.datelineText.isEmpty ? relativeTime(item.dateline) : item.datelineText)
                    if store.showsDeviceInfo, !item.deviceTitle.isEmpty {
                        Text("·")
                        Button(item.deviceTitle) { store.searchDevice(item.deviceTitle) }
                            .buttonStyle(.plain)
                    }
                    if !item.ipLocation.isEmpty { Text("· IP属地 \(item.ipLocation)") }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.openUser(item.uid)
            } label: {
                Label("主页", systemImage: "person.crop.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 26) {
            Button {
                store.toggleLike(item: item, model: nil)
                item.isLiked.toggle()
                item.likeNum += item.isLiked ? 1 : -1
            } label: {
                CountLabel(systemImage: item.isLiked ? "heart.fill" : "heart", count: item.likeNum, active: item.isLiked, activeColor: Palette.like)
            }
            .buttonStyle(.plain)
            Button {
                store.toggleCollect(item: item, model: nil)
                item.isFavorited.toggle()
                item.favNum += item.isFavorited ? 1 : -1
            } label: {
                CountLabel(systemImage: item.isFavorited ? "star.fill" : "star", count: item.favNum, active: item.isFavorited, activeColor: Palette.star)
            }
            .buttonStyle(.plain)
            CountLabel(systemImage: "bubble.right", count: item.commentNum)
            CountLabel(systemImage: "arrowshape.turn.up.right", count: item.forwardNum)
            Spacer()
            Menu {
                Button("复制正文") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(FeedHTML.plainText(item.message), forType: .string)
                }
                Button("复制链接") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://www.coolapk.com/feed/\(item.id)", forType: .string)
                }
                Button("编辑历史") { sheet = .history }
                Button("转发") {
                    guard store.requireLogin() else { return }
                    forwardText = ""
                    forwarding = true
                }
                Button("在浏览器中打开") {
                    NSWorkspace.shared.open(URL(string: "https://www.coolapk.com/feed/\(item.id)")!)
                }
                if !store.uid.isEmpty, store.uid == item.uid {
                    Divider()
                    Button("删除动态", role: .destructive) {
                        Task {
                            do {
                                try await API.deleteFeed(id: item.id)
                                store.present("已删除")
                                store.selectedFeed = nil
                            } catch {
                                store.present((error as? APIError)?.errorDescription ?? "删除失败")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
        }
        .font(.system(size: 13))
    }

    /// Secondary entry points that replace the mobile app's tap targets on desktop.
    private var quickLinks: some View {
        HStack(spacing: 16) {
            link("点赞的人", icon: "heart.text.square") { sheet = .likers }
            link(item.forwardNum > 0 ? "转发 \(formatCount(item.forwardNum))" : "转发",
                 icon: "arrowshape.turn.up.right.square") {
                sheet = .forwards
            }
            link("编辑历史", icon: "clock.arrow.circlepath") { sheet = .history }
            Spacer()
        }
        .font(.system(size: 11.5))
    }

    private func link(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10.5))
                Text(title)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var forwardSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("转发动态").font(.system(size: 15, weight: .semibold))
            TextField("说点什么…", text: $forwardText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .padding(12)
                .glassPanel(cornerRadius: 14)
            HStack {
                Spacer()
                Button("取消") { forwarding = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        do {
                            try await API.forwardFeed(id: item.id, message: forwardText.trimmingCharacters(in: .whitespacesAndNewlines))
                            forwarding = false
                            store.present("已转发")
                        } catch {
                            store.present((error as? APIError)?.errorDescription ?? "转发失败")
                        }
                    }
                } label: {
                    Text("转发").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: - Replies

    private var replySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("评论 \(item.commentNum + item.replyNum)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Picker("", selection: $replyMode) {
                    ForEach(ReplyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: replyMode) { _, _ in
                    Task { await loadReplies(reset: true) }
                }
            }

            if loadingReplies, replies.isEmpty, hotReplies.isEmpty {
                LoadingRow(text: "正在加载评论…")
            } else {
                let list = replyMode == .hot ? hotReplies : replies
                if list.isEmpty {
                    Text(store.isLoggedIn ? "还没有评论，来抢沙发吧" : "登录后查看全部评论")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(list) { reply in
                        ReplyRowView(reply: reply, feedAuthorID: item.uid) { target in
                            replyTarget = target
                        }
                        Divider().opacity(0.5)
                    }
                }
                if !finishedReplies, replyMode == .latest, !replies.isEmpty {
                    Button("加载更多评论") {
                        Task { await loadReplies(reset: false) }
                    }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .cardBackground(cornerRadius: 18)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let replyTarget {
                HStack(spacing: 6) {
                    Text("回复 @\(replyTarget.username)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Button {
                        self.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            HStack(spacing: 10) {
                TextField(store.isLoggedIn ? "发一条友善的评论" : "登录后参与评论", text: $replyText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit { send() }

                if store.isLoggedIn {
                    Button {
                        send()
                    } label: {
                        if sending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("发送").font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .tint(Palette.brand)
                } else {
                    Button("登录") { store.loginSheetPresented = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.brand)
                        .controlSize(.regular)
                }
            }
            .padding(10)
        }
        .glassPanel(cornerRadius: 16, opacity: 0.62)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .floatingBarBackdrop()
    }

    private func send() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        Task {
            do {
                let body = replyTarget.map { "回复 @\($0.username) : \(text)" } ?? text
                try await store.reply(feedID: item.id, message: body, replyID: replyTarget?.id)
                replyText = ""
                replyTarget = nil
                store.present("评论已发送")
                await loadReplies(reset: true)
            } catch {
                store.present((error as? APIError)?.errorDescription ?? "发送失败")
            }
            sending = false
        }
    }

    private func loadDetail() async {
        if let detail = try? await API.feedDetail(id: initial.id) {
            item = detail
        }
    }

    private func loadReplies(reset: Bool) async {
        if loadingReplies { return }
        loadingReplies = true
        defer { loadingReplies = false }
        if reset {
            replyPage = 1
            finishedReplies = false
        }
        do {
            if replyMode == .hot {
                if reset || hotReplies.isEmpty {
                    let hot = try await API.hotReplies(feedID: item.id, page: 1)
                    hotReplies = hot.isEmpty ? item.topReplyRows : hot
                }
            } else {
                let page = try await API.replies(feedID: item.id, page: replyPage)
                if reset { replies = [] }
                let existing = Set(replies.map(\.id))
                replies.append(contentsOf: page.filter { !existing.contains($0.id) })
                if page.isEmpty { finishedReplies = true }
                replyPage += 1
            }
        } catch {
            if replies.isEmpty, hotReplies.isEmpty, !item.topReplyRows.isEmpty {
                hotReplies = item.topReplyRows
            }
        }
    }
}

// MARK: - Reply row

struct ReplyRowView: View {
    let reply: ReplyItem
    var feedAuthorID: String = ""
    var onReply: ((ReplyItem) -> Void)?

    @Environment(AppStore.self) private var store
    @State private var nested: [ReplyItem] = []
    @State private var showNested = false
    @State private var loadingNested = false
    @State private var liked = false
    @State private var likeCount = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: reply.avatar, size: 32)
                .onTapGesture { store.openUser(reply.uid) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(reply.username)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(reply.uid == feedAuthorID ? Palette.brand : .primary)
                        .onTapGesture { store.openUser(reply.uid) }
                    if reply.uid == feedAuthorID {
                        TagChip(text: "作者", tint: Palette.brand)
                    }
                    Spacer()
                    Text(reply.datelineText.isEmpty ? relativeTime(reply.dateline) : reply.datelineText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if !reply.replyToName.isEmpty {
                    Text("回复 @\(reply.replyToName)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.brand)
                }
                RichTextView(
                    attributed: FeedHTML.cachedAttributedString(html: reply.message, fontSize: 13.5, color: .labelColor),
                    isSelectable: true,
                    onLink: { store.handle(link: $0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 16) {
                    Button {
                        guard store.requireLogin() else { return }
                        liked.toggle()
                        likeCount += liked ? 1 : -1
                        Task { try? await API.likeReply(id: reply.id, liked: liked) }
                    } label: {
                        CountLabel(systemImage: liked ? "heart.fill" : "heart", count: max(likeCount, 0), active: liked, activeColor: Palette.like)
                    }
                    .buttonStyle(.plain)

                    Button("回复") { onReply?(reply) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)

                    if reply.replyNum > 0 {
                        Button(showNested ? "收起回复" : "\(reply.replyNum) 条回复") {
                            toggleNested()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.brand)
                    }
                    Spacer()
                }

                if showNested {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(nested) { child in
                            nestedRow(child)
                        }
                        if loadingNested { LoadingRow(text: "正在加载回复…") }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            likeCount = reply.likeNum
            liked = reply.isLiked
        }
    }

    private func nestedRow(_ child: ReplyItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: child.avatar, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(child.username).font(.system(size: 12, weight: .medium))
                    Text(child.datelineText.isEmpty ? relativeTime(child.dateline) : child.datelineText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                RichTextView(
                    attributed: FeedHTML.cachedAttributedString(html: child.message, fontSize: 12.5, color: .secondaryLabelColor),
                    maxLines: 0,
                    isSelectable: true,
                    onLink: { store.handle(link: $0) }
                )
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggleNested() {
        showNested.toggle()
        guard showNested, nested.isEmpty, !loadingNested else { return }
        loadingNested = true
        Task {
            nested = (try? await API.subReplies(replyID: reply.id, page: 1)) ?? []
            loadingNested = false
        }
    }
}
