import AppKit
import SwiftUI

@main
struct CoolapkApp: App {
    @State private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .defaultSize(width: 1360, height: 880)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("发布动态") { store.showCompose = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("搜索") { store.showSearch = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("刷新") { store.refreshBadge() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("登录酷安账号…") { store.loginSheetPresented = true }
            }
            SidebarCommands()
        }
        .windowStyle(.automatic)
    }
}
