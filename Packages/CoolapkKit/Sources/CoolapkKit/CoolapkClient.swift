import Foundation

public enum APIError: LocalizedError {
    case blocked
    case expired
    case message(String)
    case network(String)
    case unauthorized
    case decoding

    public var errorDescription: String? {
        switch self {
        case .blocked: return "请求被酷安安全策略拦截，请稍后再试"
        case .expired: return "登录状态已过期，请重新登录"
        case let .message(text): return text
        case let .network(text): return text
        case .unauthorized: return "该操作需要登录酷安账号"
        case .decoding: return "数据解析失败"
        }
    }
}

/// 请求日志出口，由宿主注入（应用层只在开了 `COOLAPK_DEBUG=1` 时接管），
/// 这样包本身不依赖任何调试开关。
public enum CoolapkLog {
    public nonisolated(unsafe) static var sink: ((String) -> Void)?

    static func log(_ message: @autoclosure () -> String) {
        sink?(message())
    }
}

/// Sends signed requests to `api.coolapk.com`.
public actor CoolapkClient {
    public static let shared = CoolapkClient()

    private let session: URLSession
    private var deviceCode: String
    private var cachedToken: String?
    private var tokenDate: Date = .distantPast
    private let tokenLifetime: TimeInterval = 20 * 60

    private var loginCookie: String = ""
    private(set) var uid: String = ""
    private(set) var username: String = ""
    private var token: String = ""
    private var sessid: String = ""

    public var isLoggedIn: Bool { !self.token.isEmpty }

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate"]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        deviceCode = UserDefaults.standard.string(forKey: "coolapk.deviceCode") ?? ""
        if deviceCode.isEmpty {
            deviceCode = CoolapkToken.makeDeviceCode()
            UserDefaults.standard.set(deviceCode, forKey: "coolapk.deviceCode")
        }
    }

    // MARK: - Session

    public func updateLogin(uid: String, username: String, token: String, sessid: String) {
        self.uid = uid
        self.username = username
        self.token = token
        self.sessid = sessid
        rebuildCookie()
    }

    public func clearLogin() {
        uid = ""
        username = ""
        token = ""
        sessid = ""
        loginCookie = ""
    }

    public func sessionSnapshot() -> (uid: String, username: String, token: String, sessid: String) {
        (uid, username, token, sessid)
    }

    private func rebuildCookie() {
        var parts: [String] = []
        if !token.isEmpty { parts.append("token=\(token)") }
        if !username.isEmpty {
            let encoded = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? username
            parts.append("username=\(encoded)")
        }
        if !uid.isEmpty { parts.append("uid=\(uid)") }
        if !sessid.isEmpty { parts.append("SESSID=\(sessid)") }
        loginCookie = parts.joined(separator: "; ")
    }

    // MARK: - Token

    private func currentAppToken() async -> String {
        if let cachedToken, Date().timeIntervalSince(tokenDate) < tokenLifetime {
            return cachedToken
        }
        let code = deviceCode
        let generated = await CoolapkToken.currentToken(deviceCode: code) ?? ""
        cachedToken = generated
        tokenDate = Date()
        return generated
    }

    private func invalidateToken() {
        cachedToken = nil
        tokenDate = .distantPast
    }

    // MARK: - Requests

    private func makeRequest(
        path: String,
        parameters: [String: String],
        method: String,
        body: Data?,
        contentType: String? = "application/x-www-form-urlencoded"
    ) async throws -> Data {
        let appToken = await currentAppToken()
        var components = URLComponents(string: path.hasPrefix("http") ? path : "https://api.coolapk.com" + path)
        if !parameters.isEmpty {
            var items = components?.queryItems ?? []
            for (key, value) in parameters where !value.isEmpty {
                items.append(URLQueryItem(name: key, value: value))
            }
            components?.queryItems = items
        }
        guard let url = components?.url else { throw APIError.network("无效的请求地址") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("com.coolapk.market", forHTTPHeaderField: "X-App-Id")
        request.setValue(CoolapkToken.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(CoolapkToken.appCode, forHTTPHeaderField: "X-App-Code")
        request.setValue(CoolapkToken.appCode, forHTTPHeaderField: "X-App-Supported")
        request.setValue(CoolapkToken.apiVersion, forHTTPHeaderField: "X-Api-Version")
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue(deviceCode, forHTTPHeaderField: "X-App-Device")
        request.setValue(CoolapkToken.sdkInt, forHTTPHeaderField: "X-Sdk-Int")
        request.setValue("zh-CN", forHTTPHeaderField: "X-Sdk-Locale")
        request.setValue("universal", forHTTPHeaderField: "X-App-Mode")
        request.setValue("coolapk", forHTTPHeaderField: "X-App-Channel")
        request.setValue("0", forHTTPHeaderField: "X-Dark-Mode")
        request.setValue(CoolapkToken.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if !loginCookie.isEmpty { request.setValue(loginCookie, forHTTPHeaderField: "Cookie") }
        if let body {
            request.httpBody = body
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 567 { throw APIError.blocked }
                // 网关拦截、被 WAF 挡下这类响应是空的 HTML，直接说清楚状态码，
                // 别再让它走到 JSON 解析里报成「数据解析失败」。
                if http.statusCode != 200, (try? JSON(data: data)) == nil {
                    throw APIError.network("服务端返回异常（HTTP \(http.statusCode)）")
                }
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func perform(path: String, parameters: [String: String], method: String, body: String?) async throws -> JSON {
        var attempt = 0
        while true {
            let data = try await makeRequest(path: path, parameters: parameters, method: method, body: body.map { Data($0.utf8) })
            let json: JSON
            do {
                json = try JSON(data: data)
            } catch {
                if attempt == 0 { attempt += 1; invalidateToken(); continue }
                throw APIError.decoding
            }

            let status = json.status.int
            if !json.message.isNull, status != 0, status != 1, status != 1000, !json.data.exists {
                let text = json.message.string
                if status == 1005 || text.contains("过期") {
                    if attempt == 0 { attempt += 1; invalidateToken(); continue }
                    throw APIError.expired
                }
                if text.contains("登录") {
                    throw APIError.unauthorized
                }
                throw APIError.message(text)
            }
            if status == 1005, attempt == 0 {
                attempt += 1
                invalidateToken()
                continue
            }
            let query = parameters.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&")
            CoolapkLog.log("\(method) \(path)?\(query) -> status \(status) data \(json.data.array.count) message \(json.message.string)")
            if json.data.array.isEmpty, !json.data.isObject {
                CoolapkLog.log("  \(path) payload: \(String(data: data, encoding: .utf8)?.prefix(400) ?? "")")
            }
            return json
        }
    }

    @discardableResult
    public func get(_ path: String, _ parameters: [String: String] = [:]) async throws -> JSON {
        try await perform(path: path, parameters: parameters, method: "GET", body: nil)
    }

    @discardableResult
    public func post(_ path: String, _ form: [String: String] = [:]) async throws -> JSON {
        let body = form
            .filter { !$0.value.isEmpty }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return try await perform(path: path, parameters: [:], method: "POST", body: body)
    }

    /// Multipart upload used by the image picker in the composer.
    public func upload(path: String, fieldName: String, filename: String, data: Data, mimeType: String = "image/jpeg") async throws -> JSON {
        let boundary = "----CoolapkMac\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let raw = try await makeRequest(path: path, parameters: [:], method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        guard let json = try? JSON(data: raw) else { throw APIError.decoding }
        return json
    }

    /// `dataList` helper used by every page-style endpoint.
    public func dataList(url: String, page: Int, extra: [String: String] = [:]) async throws -> [JSON] {
        var parameters: [String: String] = ["url": url, "page": String(page), "t": String(Int(Date().timeIntervalSince1970))]
        for (key, value) in extra { parameters[key] = value }
        let json = try await get("/v6/page/dataList", parameters)
        return json.data.array
    }
}
