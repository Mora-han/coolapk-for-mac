import AppKit
import SwiftUI

public struct ViewerState: Identifiable, Hashable {
    public init(images: [String], index: Int, title: String = "") {
        self.images = images
        self.index = index
        self.title = title
    }

    public let id = UUID()
    public var images: [String]
    public var index: Int
    public var title: String = ""
}

/// Full screen image browser with zoom, pan and keyboard navigation.
public struct ImageViewerOverlay: View {
    public let state: ViewerState
    public var onClose: () -> Void

    @State private var index: Int
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var savedMessage: String?

    public init(state: ViewerState, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
        _index = State(initialValue: state.index)
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.86))
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            image
                .id(index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
                .overlay(alignment: .leading) {
                    if state.images.count > 1 {
                        arrowButton(systemImage: "chevron.left", help: "上一张") { step(-1) }
                            .padding(.leading, 14)
                    }
                }
                .overlay(alignment: .trailing) {
                    if state.images.count > 1 {
                        arrowButton(systemImage: "chevron.right", help: "下一张") { step(1) }
                            .padding(.trailing, 14)
                    }
                }

            controls
        }
        .transition(.opacity)
        .onExitCommand(perform: onClose)
        .background {
            // 左右方向键翻页，ESC 由 onExitCommand 处理。
            HStack {
                Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .overlay(alignment: .bottom) {
            if let savedMessage {
                Text(savedMessage)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassPanel(cornerRadius: 12)
                    .padding(.bottom, 26)
            }
        }
    }

    private var image: some View {
        RemoteImage(url: currentURL, maxPixel: 3_600, contentMode: .fit, showsPlaceholder: true, quality: 2)
            .scaleEffect(zoom)
            .offset(offset)
            .shadow(color: .black.opacity(0.4), radius: 24, y: 6)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(width: dragStart.width + value.translation.width,
                                        height: dragStart.height + value.translation.height)
                    }
                    .onEnded { _ in dragStart = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.22)) {
                    zoom = zoom > 1 ? 1 : 2.2
                    if zoom == 1 { offset = .zero; dragStart = .zero }
                }
            }
    }

    private var currentURL: String {
        guard state.images.indices.contains(index) else { return "" }
        return state.images[index]
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 10) {
                Text(state.images.count > 1 ? "\(index + 1) / \(state.images.count)" : state.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button {
                    zoom = max(0.4, zoom - 0.3)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("缩小")
                Button {
                    zoom = min(6, zoom + 0.3)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("放大")
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        zoom = 1
                        offset = .zero
                        dragStart = .zero
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("还原大小")
                Button {
                    save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("存储到下载文件夹")
                Button {
                    copy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制图片")
                Button {
                    setAsWallpaper()
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .help("设为桌面壁纸")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .keyboardShortcut(.escape, modifiers: [])
                .help("关闭")
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassPanel(cornerRadius: 14)
            .padding(18)

            Spacer()

            if state.images.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(state.images.enumerated()), id: \.offset) { position, url in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                index = position
                                zoom = 1
                                self.offset = .zero
                                dragStart = .zero
                            }
                        } label: {
                            RemoteImage(url: url, maxPixel: 160, contentMode: .fill, cornerRadius: 6)
                                .frame(width: 46, height: 46)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(position == index ? Color.white : Color.white.opacity(0.2), lineWidth: position == index ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .glassPanel(cornerRadius: 14)
                .padding(.bottom, 18)
            }
        }
    }

    private func save() {
        Task {
            let link = ImageStore.normalize(currentURL)
            guard let url = URL(string: link), let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            await MainActor.run {
                let name = url.lastPathComponent.isEmpty ? "coolapk-\(UUID().uuidString.prefix(6)).jpg" : url.lastPathComponent
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let target = downloads.appendingPathComponent(name)
                do {
                    try data.write(to: target)
                    flash("已存储到下载文件夹")
                    NSWorkspace.shared.activateFileViewerSelecting([target])
                } catch {
                    flash("存储失败")
                }
            }
        }
    }

    private func setAsWallpaper() {
        Task {
            let link = ImageStore.normalize(currentURL)
            guard let url = URL(string: link), let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            await MainActor.run {
                let target = FileManager.default.temporaryDirectory
                    .appendingPathComponent("coolapk-wallpaper-\(UUID().uuidString.prefix(6)).jpg")
                guard (try? data.write(to: target)) != nil else {
                    flash("设置失败")
                    return
                }
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(target, for: screen, options: [:])
                }
                flash("已设为桌面壁纸")
            }
        }
    }

    private func step(_ delta: Int) {
        let count = state.images.count
        guard count > 1 else { return }
        withAnimation(.snappy(duration: 0.2)) {
            index = (index + delta + count) % count
            zoom = 1
            offset = .zero
            dragStart = .zero
        }
    }

    private func arrowButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }

    private func copy() {
        Task {
            let link = ImageStore.normalize(currentURL)
            guard let url = URL(string: link), let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                flash("图片已复制")
            }
        }
    }

    private func flash(_ text: String) {
        savedMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if savedMessage == text { savedMessage = nil }
        }
    }
}
