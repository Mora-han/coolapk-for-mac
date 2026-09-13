import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

struct SearchView: View {
    @Environment(AppStore.self) private var store

    @State private var type: ResultType = .feeds
    @State private var results: [HomeFeedRow] = []
    @State private var users: [UserBrief] = []
    @State private var topics: [TopicItem] = []
    @State private var suggestions: [String] = []
    @State private var hotWords: [String] = []
    @State private var history: [String] = UserDefaults.standard.stringArray(forKey: "search.history") ?? []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false
    @State private var submitted: String?
    @State private var error: String?
    /// 边打边搜的防抖任务：连续输入时只发最后一次请求。
    @State private var pendingSearch: Task<Void, Never>?
    /// 点过候选词后不要再弹候选，等下一次真实输入。
    @State private var muteSuggestions = false
    /// 结果卡片按所在栏的实际宽度排版，不写死宽度。
    @State private var rowWidth: CGFloat = 320

    enum ResultType: String, CaseIterable, Identifiable {
        case feeds = "动态"
        case users = "用户"
        case topics = "话题"
        var id: String { rawValue }

        var apiType: String {
            switch self {
            case .feeds: return "feed"
            case .users: return "user"
            case .topics: return "feedTopic"
            }
        }
    }

    /// 关键词只有一处来源：侧栏左上角的搜索框。
    private var keyword: String { store.searchText }

    var body: some View {
        content
            .task {
                if hotWords.isEmpty {
                    hotWords = (try? await API.hotSearchWords()) ?? []
                }
                // 带着关键词进来时（侧栏搜索框提交、调试入口）直接出结果。
                if store.searching, !keyword.isEmpty {
                    pendingSearch?.cancel()
                    search(recordHistory: true)
                    store.searching = false
                }
            }
            .onChange(of: store.searching) { _, newValue in
                if newValue, !keyword.isEmpty {
                    pendingSearch?.cancel()
                    search(recordHistory: true)
                    store.searching = false
                }
            }
            .onChange(of: store.searchText) { _, value in
                muteSuggestions = false
                scheduleSearch()
                Task { await loadSuggestions(value) }
            }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !history.isEmpty { chipSection(title: "搜索历史", items: history, clearable: true) }
                    if !hotWords.isEmpty { chipSection(title: "酷安热搜", items: hotWords, clearable: false) }
                } else {
                    // 候选词排在结果上方，选一个就搜它。
                    if !suggestions.isEmpty { suggestionList }
                    resultsSection
                }
            }
            .frame(maxWidth: min(760, store.contentWidth + 140))
            .frame(maxWidth: .infinity)
            .padding(18)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        }
    }

    private var suggestionList: some View {
        // 候选词最多显示几条，别把底下的结果挤到屏幕外。
        let shown = Array(suggestions.prefix(6))
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(shown, id: \.self) { word in
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text(word).font(.system(size: 13))
                    Spacer()
                    Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture {
                    submit(word)
                }
            }
        }
        .padding(8)
        .cardBackground(cornerRadius: 14)
    }

    private func chipSection(title: String, items: [String], clearable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                if clearable {
                    Button("清空") {
                        history = []
                        UserDefaults.standard.set([], forKey: "search.history")
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
            FlowChips(items: items) { word in
                submit(word)
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 14)
    }

    @ViewBuilder
    private var resultsSection: some View {
        HStack(spacing: 8) {
            Text("「\(submitted ?? keyword)」的搜索结果")
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }

        Picker("", selection: $type) {
            ForEach(ResultType.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: type) { _, _ in
            guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            pendingSearch?.cancel()
            search()
        }

        if loading, results.isEmpty, users.isEmpty, topics.isEmpty {
            LoadingRow(text: "正在搜索…")
        } else {
            // 已经有结果时，错误挂在列表上方显示，不再把结果整块换掉（加载下一页失败会看不到列表）。
            if let error {
                ErrorBanner(message: error) { search() }
            }
            switch type {
            case .feeds:
                if results.isEmpty, error == nil {
                    EmptyStateView(title: "没有找到相关动态", systemImage: "text.magnifyingglass").frame(height: 200)
                }
                ForEach(results) { row in
                    FeedRowView(row: row, width: max(200, rowWidth - 36), model: FeedListModel(source: .search(submitted ?? "", "feed")))
                }
            case .users:
                if users.isEmpty, error == nil {
                    EmptyStateView(title: "没有找到相关用户", systemImage: "person.slash").frame(height: 200)
                }
                ForEach(users) { user in
                    HStack(spacing: 12) {
                        AvatarView(url: user.avatar, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.username).font(.system(size: 13.5, weight: .medium))
                            if !user.bio.isEmpty {
                                Text(FeedHTML.plainText(user.bio)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .cardBackground(cornerRadius: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { store.openUser(user.id) }
                }
            case .topics:
                if topics.isEmpty, error == nil {
                    EmptyStateView(title: "没有找到相关话题", systemImage: "number").frame(height: 200)
                }
                ForEach(topics) { topic in
                    HStack(spacing: 12) {
                        RemoteImage(url: topic.logo, maxPixel: 200, contentMode: .fill, cornerRadius: 10)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(topic.title).font(.system(size: 13.5, weight: .medium))
                            if !topic.description.isEmpty {
                                Text(FeedHTML.plainText(topic.description)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .cardBackground(cornerRadius: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { store.openTopic(topic.title) }
                }
            }

            if !finished, !(results.isEmpty && users.isEmpty && topics.isEmpty) {
                loadMoreButton
            }
        }
    }

    /// 加载下一页。整行都能点，等待期间给出转圈与文案，避免看着像没反应。
    private var loadMoreButton: some View {
        Button {
            loadMore()
        } label: {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().controlSize(.small)
                }
                Text(loading ? "正在加载…" : "加载更多")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brand)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .disabled(loading)
    }

    /// 从候选词 / 历史 / 热搜里选一个词：写回侧栏搜索框并立刻出结果。
    private func submit(_ word: String) {
        pendingSearch?.cancel()
        muteSuggestions = true
        suggestions = []
        store.searchText = word
        store.submitSearch()
    }

    /// 边打边搜：停顿一下再发请求，打字过程中不打断输入。
    private func scheduleSearch() {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSearch?.cancel()
        guard !word.isEmpty else { return }
        pendingSearch = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            search()
        }
    }

    /// 搜一次关键词。`recordHistory` 只在「真的搜了」时记（回车 / 点候选词），
    /// 边打边搜的中间状态不进历史。
    private func search(recordHistory: Bool = false) {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        submitted = word
        page = 1
        finished = false
        results = []
        users = []
        topics = []
        if recordHistory, !history.contains(word) {
            history.insert(word, at: 0)
            history = Array(history.prefix(12))
            UserDefaults.standard.set(history, forKey: "search.history")
        }
        Task { await performSearch() }
    }

    private func loadMore() {
        guard !loading, !finished, submitted != nil else { return }
        page += 1
        Task { await performSearch() }
    }

    private func performSearch() async {
        guard let word = submitted else { return }
        loading = true
        defer { loading = false }
        do {
            let items = try await API.search(keyword: word, type: type.apiType, page: page)
            switch type {
            case .feeds:
                let rows = try API.rows(from: items)
                let known = Set(results.map(\.id))
                results.append(contentsOf: rows.filter { !known.contains($0.id) })
            case .users:
                let known = Set(users.map(\.id))
                users.append(contentsOf: items.map { UserBrief(json: $0) }.filter { !known.contains($0.id) })
            case .topics:
                let known = Set(topics.map(\.id))
                topics.append(contentsOf: items.map { TopicItem(json: $0) }.filter { !known.contains($0.id) })
            }
            if items.isEmpty { finished = true }
            error = nil
        } catch {
            self.error = LoadError.message(error)
        }
    }

    private func loadSuggestions(_ value: String) async {
        let word = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.count >= 1 else {
            suggestions = []
            return
        }
        guard !muteSuggestions else { return }
        try? await Task.sleep(nanoseconds: 220_000_000)
        suggestions = (try? await API.suggestWords(keyword: word)) ?? []
    }
}

/// Simple wrapping chip layout used by search history and hot words.
struct FlowChips: View {
    let items: [String]
    var onSelect: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(item)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var current = CGSize.zero
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if current.width + size.width > maxWidth, current.width > 0 {
                current.width = 0
                current.height += lineHeight + spacing
                lineHeight = 0
            }
            current.width += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? current.width : maxWidth, height: current.height + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
