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
                .preferredColorScheme(store.appearance.colorScheme)
        }
        .defaultSize(width: 1360, height: 880)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("发布动态") { store.showCompose = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("搜索") { store.showSearch = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("刷新") {
                    store.refreshBadge()
                    store.reloadToken.toggle()
                }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("后退") { store.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("前进") { store.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("回到首页") { store.selection = .home }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                Button("登录酷安账号…") { store.loginSheetPresented = true }
            }
            SidebarCommands()
        }
        .windowStyle(.automatic)
    }
}
