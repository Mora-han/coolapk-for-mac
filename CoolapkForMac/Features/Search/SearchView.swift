import AppKit
import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store

    @State private var keyword = ""
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

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .task {
            if hotWords.isEmpty {
                hotWords = (try? await API.hotSearchWords()) ?? []
            }
        }
        .onChange(of: store.searching) { _, newValue in
            if newValue, !store.searchText.isEmpty {
                keyword = store.searchText
                search()
                store.searching = false
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12.5))
                TextField("搜索酷安、用户、话题", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { search() }
                    .onChange(of: keyword) { _, value in
                        Task { await loadSuggestions(value) }
                    }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        suggestions = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 420)

            Button("搜索") { search() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
                .controlSize(.regular)
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !suggestions.isEmpty, submitted == nil {
                    suggestionList
                } else if submitted == nil {
                    if !history.isEmpty { chipSection(title: "搜索历史", items: history, clearable: true) }
                    if !hotWords.isEmpty { chipSection(title: "酷安热搜", items: hotWords, clearable: false) }
                } else {
                    resultsSection
                }
            }
            .frame(maxWidth: min(760, store.contentWidth + 140))
            .frame(maxWidth: .infinity)
            .padding(18)
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(suggestions, id: \.self) { word in
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
                    keyword = word
                    search()
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
                keyword = word
                search()
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 14)
    }

    @ViewBuilder
    private var resultsSection: some View {
        Picker("", selection: $type) {
            ForEach(ResultType.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: type) { _, _ in search() }

        if loading, results.isEmpty, users.isEmpty, topics.isEmpty {
            LoadingRow(text: "正在搜索…")
        } else if let error {
            ErrorBanner(message: error) { search() }
        } else {
            switch type {
            case .feeds:
                ForEach(results) { row in
                    FeedRowView(row: row, width: min(760, store.contentWidth + 140) - 36, model: FeedListModel(source: .search(submitted ?? "", "feed")))
                }
            case .users:
                if users.isEmpty { EmptyStateView(title: "没有找到相关用户", systemImage: "person.slash").frame(height: 200) }
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
                    }
                    .padding(12)
                    .cardBackground(cornerRadius: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { store.openUser(user.id) }
                }
            case .topics:
                if topics.isEmpty { EmptyStateView(title: "没有找到相关话题", systemImage: "number").frame(height: 200) }
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
                    }
                    .padding(12)
                    .cardBackground(cornerRadius: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { store.openTopic(topic.title) }
                }
            }

            if !finished, !(results.isEmpty && users.isEmpty && topics.isEmpty) {
                Button("加载更多") { loadMore() }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func search() {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        submitted = word
        suggestions = []
        page = 1
        finished = false
        results = []
        users = []
        topics = []
        if !history.contains(word) {
            history.insert(word, at: 0)
            history = Array(history.prefix(12))
            UserDefaults.standard.set(history, forKey: "search.history")
        }
        Task { await performSearch() }
    }

    private func loadMore() {
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
                results.append(contentsOf: rows)
            case .users:
                users.append(contentsOf: items.map { UserBrief(json: $0) })
            case .topics:
                topics.append(contentsOf: items.map { TopicItem(json: $0) })
            }
            if items.isEmpty { finished = true }
            error = nil
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadSuggestions(_ value: String) async {
        let word = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.count >= 1, submitted == nil else {
            suggestions = []
            return
        }
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
