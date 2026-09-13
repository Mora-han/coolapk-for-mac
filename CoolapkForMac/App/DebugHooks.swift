import Foundation
import CoolapkKit

/// 仅用于自动化截图与回归测试的环境变量入口。
///
/// 支持：
/// - `COOLAPK_OPEN`：`feed:123` / `user:123` / `topic:小米` / `page:V9_HOME_TAB_RANKING` …
/// - `COOLAPK_OPEN_FEED`：直接打开某条动态详情
/// - `COOLAPK_TAB`：指定首页 Tab 的 pageName
/// - `COOLAPK_SCROLL`：列表加载完成后滚动到第 N 行（从 0 开始）
enum DebugHooks {
    /// 把包里的请求日志接到同一个出口，命令行排查时能看到服务端返回了什么。
    static func installLogSink() {
        guard isVerbose else { return }
        CoolapkLog.sink = { log($0) }
    }

    static var homeTab: String? {
        let value = ProcessInfo.processInfo.environment["COOLAPK_TAB"]
        return (value?.isEmpty == false) ? value : nil
    }

    /// `COOLAPK_NOTIFY=likes` 等，直接打开消息页的某个分类，便于回归截图。
    static var notificationKind: String? {
        let value = ProcessInfo.processInfo.environment["COOLAPK_NOTIFY"]
        return (value?.isEmpty == false) ? value : nil
    }

    static let isVerbose = ProcessInfo.processInfo.environment["COOLAPK_DEBUG"] == "1"

    /// 打开 `COOLAPK_DEBUG=1` 时把请求与错误打到标准错误，便于命令行排查；
    /// 再给一个 `COOLAPK_LOG_FILE=/tmp/coolapk.log` 时同时追加写入文件，
    /// 因为用 `open` 启动的窗口应用读不到标准错误。
    static func log(_ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        let text = "coolapk: " + message() + "\n"
        FileHandle.standardError.write(Data(text.utf8))
        // 应用开了沙盒，容器外的路径（比如 /tmp）写不进去，统一回落到容器内的临时目录。
        let requested = ProcessInfo.processInfo.environment["COOLAPK_LOG_FILE"]
        let fallback = NSTemporaryDirectory() + "coolapk-debug.log"
        let path = (requested?.isEmpty == false) ? requested! : fallback
        if !append(text, to: path) { _ = append(text, to: fallback) }
    }

    private static func append(_ text: String, to path: String) -> Bool {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
            return true
        }
        return (try? text.write(toFile: path, atomically: true, encoding: .utf8)) != nil
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
