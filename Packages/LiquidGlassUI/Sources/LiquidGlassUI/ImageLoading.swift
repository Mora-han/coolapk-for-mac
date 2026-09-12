import Foundation

/// 图片加载的全局配置。宿主 App 在启动时注入自己的 User-Agent 与偏好，
/// 这样本模块不需要了解任何具体业务。
public enum ImageLoading {
    /// 图片 CDN 要求的 User-Agent，留空则用系统默认值。
    public static var userAgent: String = ""

    /// 是否加载网络图片（关闭后只显示占位图，省流量）。
    public static var showsImages = true

    /// 0 = 极小图, 1 = 标准, 2 = 原图。
    public static var defaultQuality = 2
}
