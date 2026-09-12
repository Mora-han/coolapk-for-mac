import Foundation
import CryptoKit

/// Device identity + `X-App-Token` generation for the Coolapk open API.
enum CoolapkToken {
    static let apiVersion = "13"
    static let appVersion = "13.4.1"
    static let appCode = "2409121"

    static let userAgent =
        "Dalvik/2.1.0 (Linux; U; Android 13; \(deviceModel) Build/TKQ1.221114.001) "
        + "(#Build; \(deviceBrand); \(deviceModel); TKQ1.221114.001; 13) +CoolMarket/\(appVersion)-\(appCode)-universal"

    static let deviceBrand = "Xiaomi"
    static let deviceModel = "M2102J2SC"

    // MARK: - Hashing helpers

    static func md5(_ input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func base64(_ input: String, padding: Bool) -> String {
        var encoded = Data(input.utf8).base64EncodedString()
        if !padding { encoded = encoded.replacingOccurrences(of: "=", with: "") }
        return encoded
    }

    static func randomHex(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// `X-App-Device` value: `base64(aid; ; ; mac; manufacture; brand; model; build; null)` reversed.
    static func makeDeviceCode() -> String {
        let aid = randomHex(16)
        let mac = (0..<6).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined(separator: ":")
        let raw = "\(aid); ; ; \(mac); \(deviceBrand); \(deviceBrand); \(deviceModel); unknown; null"
        return String(base64(raw, padding: false).reversed())
    }

    // MARK: - Tokens

    /// Legacy token (schema v1). Kept as a fallback for endpoints that prefer it.
    static func appTokenV1(deviceCode: String, timestamp: Int) -> String {
        let time = String(timestamp)
        let token = "token://com.coolapk.market/c67ef5943784d09750dcfbb31020f0ab?"
            + "\(md5(time))$\(md5(deviceCode))&com.coolapk.market"
        let hashed = md5(base64(token, padding: true))
        return "\(hashed)-\(deviceCode)\(String(timestamp, radix: 16))"
    }

    /// Current token schema. The inner bcrypt hash is what the server validates.
    static func appTokenV2(deviceCode: String, timestamp: Int) -> String? {
        let time = String(timestamp)
        let token = "token://com.coolapk.market/dcf01e569c1e3db93a3d0fcf191a622c?"
            + "\(md5(time))$\(md5(deviceCode))&com.coolapk.market"
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

    /// Token for the current moment, generated off the main thread.
    static func currentToken(deviceCode: String, timestamp: Int = Int(Date().timeIntervalSince1970)) async -> String? {
        await Task.detached(priority: .userInitiated) {
            appTokenV2(deviceCode: deviceCode, timestamp: timestamp)
        }.value
    }
}
