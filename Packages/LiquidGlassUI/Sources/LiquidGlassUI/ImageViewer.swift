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

            controls
        }
        .transition(.opacity)
        .onExitCommand(perform: onClose)
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
                    save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("存储图片")
                Button {
                    copy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制图片")
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
                let panel = NSSavePanel()
                panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "coolapk-image.jpg" : url.lastPathComponent
                if panel.runModal() == .OK, let target = panel.url {
                    try? data.write(to: target)
                    flash("已存储到 \(target.lastPathComponent)")
                }
            }
        }
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
