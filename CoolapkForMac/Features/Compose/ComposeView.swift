import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Publishes a new dynamic (动态) with optional images.
struct ComposeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var images: [NSImage] = []
    @State private var uploaded: [String] = []
    @State private var uploading = false
    @State private var publishing = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("发布动态").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button {
                    publish()
                } label: {
                    if publishing { ProgressView().controlSize(.small) } else { Text("发布") }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
                .controlSize(.small)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || publishing || uploading)
            }
            .padding(12)
            Divider()

            TextEditor(text: $message)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 190)
                .padding(10)

            if !images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        images.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(3)
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 88)
            }

            Divider()
            HStack(spacing: 12) {
                Button {
                    pickImages()
                } label: {
                    Label("添加图片", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(uploading)

                if uploading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在上传图片…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                if !uploaded.isEmpty {
                    Text("已上传 \(uploaded.count) 张").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(message.count) 字").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(10)

            if let error {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 560, height: images.isEmpty ? 340 : 430)
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let image = NSImage(contentsOf: url) else { continue }
            images.append(image)
            upload(url: url)
        }
    }

    private func upload(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        uploading = true
        Task {
            do {
                let link = try await API.uploadImage(data: data, filename: url.lastPathComponent)
                uploaded.append(link)
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "图片上传失败"
            }
            uploading = false
        }
    }

    private func publish() {
        publishing = true
        Task {
            do {
                try await API.createFeed(message: message, pictures: uploaded)
                store.present("动态发布成功")
                dismiss()
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "发布失败，请稍后再试"
            }
            publishing = false
        }
    }
}
