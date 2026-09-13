import Foundation
import CoolapkKit

/// 列表 / 详情加载的统一错误文案。
///
/// 切换页面或视图重建会取消正在飞行的请求，`URLSession` 抛出的是取消错误，
/// 这不是真的失败，直接吞掉即可，否则界面上会弹出
/// “未能完成操作。（Swift.CancellationError 错误 1。）” 这类噪声提示。
enum LoadError {
    static func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let urlError = error as? URLError, urlError.code == .cancelled { return nil }
        return (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
