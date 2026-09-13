import AppKit
import SwiftUI
import CoolapkKit
import LiquidGlassUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var cacheSize = "计算中…"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                account
                reading
                cache
                about
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(18)
        }
        .task { await updateCacheSize() }
    }

    private var account: some View {
        section("账号") {
            HStack(spacing: 12) {
                AvatarView(url: store.avatar, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isLoggedIn ? store.username : "未登录")
                        .font(.system(size: 13.5, weight: .medium))
                    Text(store.isLoggedIn ? "UID \(store.uid)" : "登录后可使用关注、评论、发布等功能")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoggedIn {
                    Button("退出登录") { store.logout() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("登录") { store.loginSheetPresented = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.brand)
                        .controlSize(.small)
                }
            }
        }
    }

    private var reading: some View {
        section("阅读") {
            Picker("外观", selection: Binding(get: { store.appearance }, set: { store.appearance = $0 })) {
                ForEach(AppStore.Appearance.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Toggle("显示图片", isOn: Binding(get: { store.showImages }, set: { store.showImages = $0; store.persist() }))
            Toggle("加载高清图片", isOn: Binding(get: { store.usesHighQualityImages }, set: { store.usesHighQualityImages = $0; store.persist() }))
            Toggle("显示设备信息", isOn: Binding(get: { store.showsDeviceInfo }, set: { store.showsDeviceInfo = $0; store.persist() }))
            HStack {
                Text("正文字号")
                Slider(value: Binding(get: { store.fontSize }, set: { store.fontSize = $0; store.persist() }), in: 13...20, step: 1)
                    .frame(width: 200)
                Text("\(Int(store.fontSize)) pt").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 44)
            }
            HStack {
                Text("内容宽度")
                Slider(value: Binding(get: { store.contentWidth }, set: { store.contentWidth = $0; store.persist() }), in: 520...820, step: 20)
                    .frame(width: 200)
                Text("\(Int(store.contentWidth))").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 44)
            }
        }
    }

    private var cache: some View {
        section("缓存") {
            HStack {
                Text("图片缓存")
                Spacer()
                Text(cacheSize).foregroundStyle(.secondary).font(.system(size: 12))
                Button("清除") {
                    Task {
                        await ImageStore.shared.clearDiskCache()
                        await updateCacheSize()
                        store.present("缓存已清除")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// 版本号直接读打包信息，跟 git tag 保持一致（0.x.x 小版本）。
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var about: some View {
        section("关于") {
            HStack {
                Text("酷安 for Mac")
                Spacer()
                Text("版本 \(Self.appVersion)").foregroundStyle(.secondary).font(.system(size: 12))
            }
            Text("第三方非官方客户端，基于酷安开放接口实现，数据版权归酷安所有。仅供学习交流使用。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("访问酷安官网") {
                    NSWorkspace.shared.open(URL(string: "https://www.coolapk.com")!)
                }
                .buttonStyle(.link)
                Button("查看开源项目") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Coolapk-UWP/Coolapk-UWP")!)
                }
                .buttonStyle(.link)
            }
            .font(.system(size: 12))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            content()
                .font(.system(size: 12.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func updateCacheSize() async {
        let size = await ImageStore.shared.diskCacheSize()
        cacheSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
