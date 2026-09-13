import SwiftUI
import CoolapkKit
import LiquidGlassUI

/// 首页 with the 关注 / 头条 / 热榜 … tab pills.
struct HomeTimelineView: View {
    @Environment(AppStore.self) private var store
    @State private var models: [String: FeedListModel] = [:]
    @State private var model: FeedListModel?

    private var selected: String { store.homeTab }

    /// 推荐流（`/v6/main/indexV8`）不在接口返回的标签列表里，单独补一个。
    private static let recommendTab = HomeTab(id: "V9_HOME_TAB_RECOMMEND", title: "推荐", pageName: "V9_HOME_TAB_RECOMMEND")

    private var tabs: [HomeTab] {
        var list = fallbackTabs
        if let section = store.sidebarSections.first(where: { $0.title.contains("首页") }) ?? store.sidebarSections.first {
            if !section.tabs.isEmpty { list = section.tabs }
        }
        if !list.contains(where: { $0.pageName == Self.recommendTab.pageName }) {
            list.insert(Self.recommendTab, at: 0)
        }
        return list
    }

    /// 接口还没返回标签时的兜底列表。
    private var fallbackTabs: [HomeTab] {
        [
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
        // 用 onAppear / onChange 同步建模型：.task 是异步的，
        // 同一个 Tab 可能被并发建出两个实例，加载的是 A、显示的却是空的 B。
        .onAppear { activateModel() }
        .onChange(of: selected) { _, _ in activateModel() }
    }

    private func activateModel() {
        let active: FeedListModel
        if let existing = models[selected] {
            active = existing
        } else {
            active = makeModel(for: selected)
            models[selected] = active
        }
        if model !== active { model = active }
    }

    private var tabBar: some View {
        GlassPillBar(
            items: tabs,
            title: \.title,
            isSelected: { $0.pageName == selected },
            onSelect: { store.homeTab = $0.pageName }
        )
    }

    private func makeModel(for pageName: String) -> FeedListModel {
        switch pageName {
        case "V9_HOME_TAB_RECOMMEND":
            return FeedListModel(source: .home)
        case "V9_HOME_TAB_HEADLINE":
            return FeedListModel(source: .headline)
        case "V9_HOME_TAB_FOLLOW":
            return FeedListModel(source: .page("V9_HOME_TAB_FOLLOW", "circle"))
        default:
            return FeedListModel(source: .page(pageName, nil))
        }
    }
}
