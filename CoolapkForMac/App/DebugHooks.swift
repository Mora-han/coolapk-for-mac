import Foundation

/// 仅用于自动化截图与回归测试的环境变量入口。
///
/// 支持：
/// - `COOLAPK_OPEN`：`feed:123` / `user:123` / `topic:小米` / `page:V9_HOME_TAB_RANKING` …
/// - `COOLAPK_OPEN_FEED`：直接打开某条动态详情
/// - `COOLAPK_TAB`：指定首页 Tab 的 pageName
/// - `COOLAPK_SCROLL`：列表加载完成后滚动到第 N 行（从 0 开始）
enum DebugHooks {
    static var homeTab: String? {
        let value = ProcessInfo.processInfo.environment["COOLAPK_TAB"]
        return (value?.isEmpty == false) ? value : nil
    }

    static let isVerbose = ProcessInfo.processInfo.environment["COOLAPK_DEBUG"] == "1"

    /// 打开 `COOLAPK_DEBUG=1` 时把请求与错误打到标准错误，便于命令行排查。
    static func log(_ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        FileHandle.standardError.write(Data(("coolapk: " + message() + "\n").utf8))
    }
}

/// 列表滚动定位，供截图与人工核对使用。
enum DebugScroll {
    static var targetRow: Int? {
        guard let raw = ProcessInfo.processInfo.environment["COOLAPK_SCROLL"], let value = Int(raw) else { return nil }
        return value >= 0 ? value : nil
    }

    /// 详情页是否自动滚动到评论区。
    static var scrollsToReplies: Bool {
        ProcessInfo.processInfo.environment["COOLAPK_DETAIL_SCROLL"] == "replies"
    }
}
