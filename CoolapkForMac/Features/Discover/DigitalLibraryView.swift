import SwiftUI
import CoolapkKit
import LiquidGlassUI

/// 数码库（`/product/categoryList`）：顶部分类胶囊 + 分类下的商品流。
///
/// 这个入口在 `/v6/main/init` 里的地址是 `/product/categoryList`，
/// 不是信息流页名，所以要按分类自己给的地址去请求商品列表。
struct DigitalLibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var categories: [ProductCategory] = []
    @State private var selected = ""
    @State private var model: FeedListModel?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            if !categories.isEmpty {
                GlassPillBar(
                    items: categories,
                    title: \.title,
                    isSelected: { $0.id == selected },
                    onSelect: { select($0) }
                )
                Divider().opacity(0.4)
            }

            if let model {
                FeedListView(model: model, emptyMessage: "这个分类下还没有商品")
            } else if failed {
                EmptyStateView(title: "数码库暂时打不开", systemImage: "cube.box")
                    .frame(maxHeight: .infinity)
            } else {
                LoadingRow().frame(maxHeight: .infinity)
            }
        }
        .task {
            guard categories.isEmpty else { return }
            let loaded = (try? await API.productCategories()) ?? []
            categories = loaded
            failed = loaded.isEmpty
            if let first = loaded.first { select(first) }
        }
    }

    private func select(_ category: ProductCategory) {
        guard selected != category.id else { return }
        selected = category.id
        model = FeedListModel(source: .dataList(category.link))
    }
}
