import AppKit
import SwiftUI

/// 带内存/磁盘缓存与降采样的远程图片。所有网络图片都经过这里。
public struct RemoteImage: View {
    public init(url: String, maxPixel: Int = 1_200, contentMode: ContentMode = .fill, showsPlaceholder: Bool = true, cornerRadius: CGFloat = 0, quality: Int = 2) {
        self.url = url
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        self.showsPlaceholder = showsPlaceholder
        self.cornerRadius = cornerRadius
        self.quality = quality
    }

    public let url: String
    public var maxPixel: Int = 1_200
    public var contentMode: ContentMode = .fill
    public var showsPlaceholder = true
    public var cornerRadius: CGFloat = 0
    public var quality: Int = 2

    @State private var image: NSImage?
    @State private var failed = false
    @State private var hovering = false

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if showsPlaceholder {
                ZStack {
                    Rectangle().fill(Palette.fill)
                    if failed {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(.tertiary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                Color.clear
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            image = nil
            failed = false
            guard ImageLoading.showsImages, !url.isEmpty else {
                failed = true
                return
            }
            let link = ImageStore.resized(ImageStore.normalize(url), quality: quality)
            if let loaded = await ImageStore.shared.image(for: link, maxPixel: maxPixel) {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

public struct AvatarView: View {
    public init(url: String, size: CGFloat = 38, level: Int = 0) {
        self.url = url
        self.size = size
        self.level = level
    }

    public let url: String
    public var size: CGFloat = 38
    public var level: Int = 0

    public var body: some View {
        RemoteImage(url: url, maxPixel: Int(size * 3.5), contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 0.6))
    }
}

/// 单图展示：按图片真实比例布局。
/// - `.crop`：限制最大高度，超出部分裁掉并显示「长图」标记（用于列表，保持版面整齐）。
/// - `.fit`：完整显示整张图片（用于详情页，不丢失内容）。
public struct AdaptiveRemoteImage: View {
    public init(url: String, maxWidth: CGFloat, maxHeight: CGFloat = 560, mode: Mode = .crop, quality: Int = 2, cornerRadius: CGFloat = 12, onTap: (() -> Void)? = nil) {
        self.url = url
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.mode = mode
        self.quality = quality
        self.cornerRadius = cornerRadius
        self.onTap = onTap
    }

    public enum Mode { case crop, fit }

    public let url: String
    public var maxWidth: CGFloat
    public var maxHeight: CGFloat = 560
    public var mode: Mode = .crop
    public var quality: Int = 2
    public var cornerRadius: CGFloat = 12
    public var onTap: (() -> Void)?

    @State private var image: NSImage?
    @State private var failed = false
    @State private var hovering = false

    /// 宽高比；未加载完成时用一个接近方形的默认值，避免版面剧烈跳动。
    private var aspect: CGFloat {
        guard let image, image.size.height > 0, image.size.width > 0 else { return 1.35 }
        return min(max(image.size.width / image.size.height, 0.24), 4.5)
    }

    private var naturalHeight: CGFloat { maxWidth / aspect }

    private var height: CGFloat {
        switch mode {
        case .crop: return min(naturalHeight, maxHeight)
        case .fit: return min(naturalHeight, maxHeight * 2.2)
        }
    }

    private var isLongImage: Bool {
        mode == .crop && naturalHeight > maxHeight + 1
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(Palette.fill)
                    if failed {
                        Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.tertiary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .frame(width: maxWidth, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if isLongImage {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .bold))
                    Text("长图").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassChip(cornerRadius: 7, tint: .black.opacity(0.28))
                .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering, onTap != nil {
                Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.16), value: hovering)
        .animation(.snappy(duration: 0.2), value: image != nil)
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        guard ImageLoading.showsImages, !url.isEmpty else {
            failed = true
            return
        }
        let link = ImageStore.resized(ImageStore.normalize(url), quality: quality)
        if let loaded = await ImageStore.shared.image(for: link, maxPixel: 1_800) {
            image = loaded
        } else {
            failed = true
        }
    }
}
