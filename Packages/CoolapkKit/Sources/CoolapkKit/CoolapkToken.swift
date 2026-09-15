import Foundation
import CryptoKit

/// Device identity + `X-App-Token` generation for the Coolapk open API.
public enum CoolapkToken {
    public static let apiVersion = "16"
    public static let appVersion = "16.2.0"
    public static let appCode = "2604201"
    /// `X-App-Code` 的数值形式，v3 token 的密码查找表按它分片。
    public static let versionCode = 2604201
    public static let sdkInt = "35"

    public static let userAgent =
        "Dalvik/2.1.0 (Linux; U; Android 16; \(deviceModel) Build/TKQ1.221114.001) "
        + "(#Build; \(deviceBrand); \(deviceModel); TKQ1.221114.001; 16) +CoolMarket/\(appVersion)-\(appCode)-universal"

    public static let deviceBrand = "Xiaomi"
    public static let deviceModel = "M2102J2SC"

    public static let packageName = "com.coolapk.market"

    // MARK: - Hashing helpers

    public static func md5(_ input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func md5(_ input: Data) -> String {
        Insecure.MD5.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    public static func base64(_ input: String, padding: Bool) -> String {
        var encoded = Data(input.utf8).base64EncodedString()
        if !padding { encoded = encoded.replacingOccurrences(of: "=", with: "") }
        return encoded
    }

    public static func randomHex(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// `X-App-Device` value: `base64(aid; ; ; mac; manufacture; brand; model; build; null)` reversed.
    public static func makeDeviceCode() -> String {
        let aid = randomHex(16)
        let mac = (0..<6).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined(separator: ":")
        let raw = "\(aid); ; ; \(mac); \(deviceBrand); \(deviceBrand); \(deviceModel); unknown; null"
        return String(base64(raw, padding: false).reversed())
    }

    // MARK: - Tokens

    /// Legacy token (schema v1). Kept as a fallback for endpoints that prefer it.
    public static func appTokenV1(deviceCode: String, timestamp: Int) -> String {
        let time = String(timestamp)
        let token = "token://\(packageName)/c67ef5943784d09750dcfbb31020f0ab?"
            + "\(md5(time))$\(md5(deviceCode))&\(packageName)"
        let hashed = md5(base64(token, padding: true))
        return "\(hashed)-\(deviceCode)\(String(timestamp, radix: 16))"
    }

    /// 上一代 token（schema v2）。服务端目前仍然接受（跟其他头一起构成「客户端身份」），
    /// 但 v2 不带版本号，官方 16.x 客户端已经改用 v3，这里留作对照与回退。
    public static func appTokenV2(deviceCode: String, timestamp: Int) -> String? {
        let time = String(timestamp)
        let token = "token://\(packageName)/dcf01e569c1e3db93a3d0fcf191a622c?"
            + "\(md5(time))$\(md5(deviceCode))&\(packageName)"
        let base64Token = base64(token, padding: false)
        let md5Base64Token = md5(base64Token)

        let raw = "$2y$10$" + base64(time, padding: false) + "/" + md5(token)
        guard raw.count >= 29 else { return nil }
        let start = raw.index(raw.startIndex, offsetBy: 7)
        let end = raw.index(start, offsetBy: 22)
        let extracted = String(raw[start..<end])

        // BCrypt.Net decodes the 22 character slice with the bcrypt alphabet before hashing,
        // so the canonical round trip has to happen here as well.
        let canonical = BCrypt.base64Encode(Array(BCrypt.base64Decode(Array(extracted.utf8)).prefix(16)))
        guard let hash = BCrypt.hash(password: Array(md5Base64Token.utf8), salt: "$2y$10$" + canonical) else {
            return nil
        }
        return "v2" + base64(hash, padding: false)
    }

    /// 当前 token（schema v3，官方 16.x 客户端用的这一代）。bcrypt 的密码由内置查找表按
    /// 时间戳取片段算出，盐里带着同一个时间戳，服务端据此重算一遍来校验。
    ///
    /// 查找表的分片和 `versionCode` 绑定：用内置这张表（2604201）生成的 token，必须配
    /// `X-App-Code: 2604201` 发出去，换成别的版本号服务端会算成另一片而验不过。
    ///
    /// 盐必须是 22 个 bcrypt 字母表内的字符，且最后一位落在规范位上，否则服务端
    /// 解出来的盐会对不上；碰上这种时间戳就往后挪一秒重试。
    public static func appTokenV3(deviceCode: String, timestamp: Int) -> String? {
        let table = TokenTableV3.bytes
        let md5Device = md5(deviceCode)
        for offset in 0...maxSaltProbe {
            let stamp = timestamp + offset
            guard let segment = tableSegment(for: stamp, table: table) else { return nil }
            var plain = Data("\(packageName)&".utf8)
            plain.append(segment)
            plain.append(Data("&\(md5Device)&\(stamp)&\(versionCode)".utf8))

            let password = md5(plain.base64EncodedString())
            let saltSource = base64("\(String(stamp, radix: 16))/\(md5(plain))", padding: false)
            guard let salt = canonicalSalt(from: saltSource) else { continue }
            guard let hash = BCrypt.hash(password: Array(password.utf8), salt: "$2y$10$" + salt) else { continue }
            return "v3" + base64(hash, padding: false)
        }
        return nil
    }

    /// Token for the current moment, generated off the main thread.
    public static func currentToken(deviceCode: String, timestamp: Int = Int(Date().timeIntervalSince1970)) async -> String? {
        await Task.detached(priority: .userInitiated) {
            appTokenV3(deviceCode: deviceCode, timestamp: timestamp)
        }.value
    }

    // MARK: - v3 helpers

    /// 服务端只认规范盐，一秒一个时间戳地往后试，够用了。
    private static let maxSaltProbe = 15

    private static let standardAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let bcryptAlphabet = Array("./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)

    /// 查找表按 `(时间戳 + 版本号) % 100` 分成 100 片，每片是一段 128 字符的 base64。
    private static func tableSegment(for timestamp: Int, table: [UInt8]) -> Data? {
        let index = ((timestamp + versionCode) % 100) * 4 + 0x80
        guard index >= 0, index + 0x80 <= table.count else { return nil }
        let chunk = String(decoding: table[index ..< index + 0x80], as: UTF8.self)
        return Data(base64Encoded: chunk)
    }

    /// 盐的来源是标准 base64，最后一位要往前挪 5 位才落在 bcrypt 的规范位上；
    /// 挪完仍不合规（或前 21 位里有 bcrypt 之外的字符）就换一个时间戳。
    private static func canonicalSalt(from source: String) -> String? {
        guard source.count >= 22 else { return nil }
        let head = Array(source.utf8.prefix(21))
        guard head.allSatisfy(bcryptAlphabet.contains) else { return nil }
        guard let last = source.dropFirst(21).first,
              let ascii = last.asciiValue,
              let index = standardAlphabet.firstIndex(of: ascii) else { return nil }
        let shifted = standardAlphabet[(index - 5 + standardAlphabet.count) % standardAlphabet.count]
        guard let shiftedIndex = bcryptAlphabet.firstIndex(of: shifted), shiftedIndex % 16 == 0 else { return nil }
        return String(decoding: head + [shifted], as: UTF8.self)
    }
}
