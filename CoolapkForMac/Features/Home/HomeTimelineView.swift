import SwiftUI
import CoolapkKit
import LiquidGlassUI

/// 首页 with the 关注 / 头条 / 热榜 … tab pills.
struct HomeTimelineView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: String = "V9_HOME_TAB_HEADLINE"
    @State private var models: [String: FeedListModel] = [:]
    @State private var model: FeedListModel?

    private var tabs: [HomeTab] {
        if let section = store.sidebarSections.first(where: { $0.title.contains("首页") }) ?? store.sidebarSections.first {
            let filtered = section.tabs
            if !filtered.isEmpty { return filtered }
        }
        return [
            HomeTab(id: "V9_HOME_TAB_FOLLOW", title: "关注", pageName: "V9_HOME_TAB_FOLLOW"),
            HomeTab(id: "V9_HOME_TAB_HEADLINE", title: "头条", pageName: "V9_HOME_TAB_HEADLINE"),
            HomeTab(id: "V9_HOME_TAB_RANKING", title: "热榜", pageName: "V9_HOME_TAB_RANKING"),
            HomeTab(id: "V11_HOME_TAB_NEWS", title: "快讯", pageName: "V11_HOME_TAB_NEWS"),
            HomeTab(id: "V11_VERTICAL_TOPIC", title: "话题", pageName: "V11_VERTICAL_TOPIC"),
            HomeTab(id: "V9_HOME_TAB_SHIPIN", title: "视频", pageName: "V9_HOME_TAB_SHIPIN"),
            HomeTab(id: "V9_HOME_TAB_WENDA", title: "问答", pageName: "V9_HOME_TAB_WENDA"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().opacity(0.4)
            if let model {
                FeedListView(
                    model: model,
                    requiresLogin: selected == "V9_HOME_TAB_FOLLOW"
                )
            } else {
                LoadingRow()
                    .frame(maxHeight: .infinity)
            }
        }
        .task(id: selected) {
            if let existing = models[selected] {
                model = existing
                return
            }
            let created = makeModel(for: selected)
            models[selected] = created
            model = created
        }
    }

    private var tabBar: some View {
        GlassPillBar(
            items: tabs,
            title: \.title,
            isSelected: { $0.pageName == selected },
            onSelect: { selected = $0.pageName }
        )
    }

    private func makeModel(for pageName: String) -> FeedListModel {
        if pageName == "V9_HOME_TAB_HEADLINE" {
            return FeedListModel(source: .home)
        } else if pageName == "V9_HOME_TAB_FOLLOW" {
            return FeedListModel(source: .page("V9_HOME_TAB_FOLLOW", "circle"))
        }
        return FeedListModel(source: .page(pageName, nil))
    }
}
