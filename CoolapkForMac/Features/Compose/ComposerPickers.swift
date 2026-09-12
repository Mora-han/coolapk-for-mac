import AppKit
import CoolapkKit
import LiquidGlassUI
import SwiftUI

/// 发布框里的插入面板：表情、@用户、#话题#。
struct ComposerInsertPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case emoji = "表情"
        case mention = "@用户"
        case topic = "#话题#"
        var id: String { rawValue }
    }

    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .emoji
    @State private var keyword = ""
    @State private var users: [UserBrief] = []
    @State private var topics: [TopicItem] = []
    @State private var searching = false

    private let emojiColumns = [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)]

    private var emojis: [String] {
        let all = EmojiStore.allNames
        guard !keyword.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { value in Text(value.rawValue).tag(value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            if mode != .emoji {
                TextField(mode == .mention ? "搜索用户" : "搜索话题", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassPanel(cornerRadius: 10)
                    .padding(.horizontal, 10)
                    .onSubmit { Task { await search() } }
                    .task(id: keyword) {
                        try? await Task.sleep(nanoseconds: 320_000_000)
                        await search()
                    }
            } else {
                TextField("搜索表情", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassPanel(cornerRadius: 10)
                    .padding(.horizontal, 10)
            }

            ScrollView {
                switch mode {
                case .emoji:
                    LazyVGrid(columns: emojiColumns, spacing: 6) {
                        ForEach(emojis, id: \.self) { name in
                            Button {
                                onInsert(name)
                            } label: {
                                if let image = EmojiStore.image(named: name) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Text(name).font(.system(size: 9))
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 34, height: 34)
                            .help(name)
                        }
                    }
                    .padding(10)
                case .mention:
                    LazyVStack(spacing: 6) {
                        ForEach(users) { user in
                            row(title: user.username, subtitle: user.bio, avatar: user.avatar, trailing: "@\(user.username)") {
                                onInsert("@\(user.username) ")
                            }
                        }
                        if searching { LoadingRow() }
                        if users.isEmpty, !searching, !keyword.isEmpty { empty("没有找到用户") }
                    }
                    .padding(10)
                case .topic:
                    LazyVStack(spacing: 6) {
                        ForEach(topics) { topic in
                            row(title: topic.title, subtitle: topic.description, avatar: topic.logo, trailing: "#\(topic.title)#") {
                                onInsert("#\(topic.title)# ")
                            }
                        }
                        if searching { LoadingRow() }
                        if topics.isEmpty, !searching, !keyword.isEmpty { empty("没有找到话题") }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 380, height: 340)
    }

    private func row(title: String, subtitle: String, avatar: String, trailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AvatarView(url: avatar, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5)).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(FeedHTML.plainText(subtitle))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(trailing).font(.system(size: 11)).foregroundStyle(Palette.brand)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 10))
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private func search() async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            users = []
            topics = []
            return
        }
        searching = true
        defer { searching = false }
        switch mode {
        case .mention:
            users = (try? await API.searchUsers(keyword: query)) ?? []
        case .topic:
            topics = (try? await API.searchTags(keyword: query)) ?? []
        case .emoji:
            break
        }
    }
}
