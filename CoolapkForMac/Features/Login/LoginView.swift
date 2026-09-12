import AppKit
import SwiftUI
import WebKit

/// Signs in through the official web login and captures the session cookies.
struct LoginSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var status = "正在打开酷安登录页…"
    @State private var manualUID = ""
    @State private var manualUsername = ""
    @State private var manualToken = ""
    @State private var showManual = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("登录酷安", systemImage: "person.badge.key")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle("手动填写 Cookie", isOn: $showManual)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Button("关闭") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(12)
            Divider()

            if showManual {
                manualForm
            } else {
                ZStack {
                    LoginWebView { uid, username, token, sessid in
                        store.saveSession(uid: uid, username: username, token: token, sessid: sessid)
                        status = "登录成功，欢迎 \(username)"
                        dismiss()
                    }
                    .frame(minWidth: 760, minHeight: 560)
                }
            }

            Divider()
            HStack {
                Text(status).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Text("登录信息仅保存在本机")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
        }
        .frame(width: showManual ? 520 : 820, height: showManual ? 360 : 660)
    }

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("在浏览器登录 coolapk.com 后，从开发者工具复制 Cookie，或直接填写以下字段。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("uid", text: $manualUID)
            TextField("username", text: $manualUsername)
            TextField("token", text: $manualToken)
            HStack {
                Spacer()
                Button("保存登录信息") {
                    guard !manualUID.isEmpty, !manualToken.isEmpty else {
                        status = "uid 与 token 不能为空"
                        return
                    }
                    store.saveSession(uid: manualUID, username: manualUsername, token: manualToken, sessid: "")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
    }
}

/// WKWebView that watches for the Coolapk session cookies.
struct LoginWebView: NSViewRepresentable {
    var onLogin: (String, String, String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLogin: onLogin) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        if let url = URL(string: "https://account.coolapk.com/auth/loginByCoolapk") {
            webView.load(URLRequest(url: url))
        }
        context.coordinator.startPolling()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLogin: (String, String, String, String) -> Void
        private var timer: Timer?
        private var finished = false

        init(onLogin: @escaping (String, String, String, String) -> Void) {
            self.onLogin = onLogin
        }

        func startPolling() {
            timer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { [weak self] _ in
                self?.checkCookies()
            }
        }

        deinit { timer?.invalidate() }

        private func checkCookies() {
            guard !finished else { return }
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                var values: [String: String] = [:]
                for cookie in cookies where cookie.domain.contains("coolapk.com") {
                    values[cookie.name] = cookie.value
                }
                guard let token = values["token"], !token.isEmpty,
                      let uid = values["uid"], !uid.isEmpty else { return }
                let username = (values["username"] ?? "").removingPercentEncoding ?? values["username"] ?? ""
                let sessid = values["SESSID"] ?? ""
                self.finished = true
                self.timer?.invalidate()
                DispatchQueue.main.async {
                    self.onLogin(uid, username, token, sessid)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkCookies()
        }
    }
}
