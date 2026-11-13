import Foundation
import Security

/// Web 访问配置：开关、端口、访问令牌。
/// 令牌是唯一凭据（局域网内谁能拿到它就能调用能力），因此优先放 Keychain，Keychain 不可用时降级到 UserDefaults。
final class WebAccessSettings {

    static let shared = WebAccessSettings()

    enum Key {
        static let enabled = "webaccess.enabled"
        static let port    = "webaccess.port"
        static let autoStart = "webaccess.autoStart"
    }

    private let defaults = UserDefaults.standard
    private let tokenService = "com.kinter.host.webaccess"
    private let tokenAccount = "access-token"
    private let tokenDefaultsKey = "webaccess.token.fallback"

    static let defaultPort: UInt16 = 8765
    /// 建议端口范围：非特权端口，避开常见服务（80/443/8080 等留给别的用途）
    static let portRange: ClosedRange<UInt16> = 1024...65535

    private init() {}

    // MARK: - 开关

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// 启动 App 时自动拉起服务（用户上次开着就自动开）
    var autoStart: Bool {
        get { defaults.bool(forKey: Key.autoStart) }
        set { defaults.set(newValue, forKey: Key.autoStart) }
    }

    // MARK: - 端口

    var port: UInt16 {
        get {
            let v = defaults.integer(forKey: Key.port)
            guard v > 0, Self.portRange.contains(UInt16(v)) else { return Self.defaultPort }
            return UInt16(v)
        }
        set {
            let clamped = min(max(newValue, Self.portRange.lowerBound), Self.portRange.upperBound)
            defaults.set(Int(clamped), forKey: Key.port)
        }
    }

    // MARK: - 令牌

    /// 首次访问时自动生成并持久化
    var token: String {
        if let saved = readToken(), !saved.isEmpty { return saved }
        let fresh = Self.generateToken()
        _ = writeToken(fresh)
        return fresh
    }

    /// 重新生成令牌（旧令牌立即失效）
    @discardableResult
    func rotateToken() -> String {
        let fresh = Self.generateToken()
        _ = writeToken(fresh)
        return fresh
    }

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 常量时间比较，避免令牌被逐位试探
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    // MARK: - Keychain

    private func readToken() -> String? {
        if let kc = readKeychain() { return kc }
        return defaults.string(forKey: tokenDefaultsKey)
    }

    @discardableResult
    private func writeToken(_ value: String) -> Bool {
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            defaults.removeObject(forKey: tokenDefaultsKey)
            return true
        }
        // 未签名构建等环境下 Keychain 不可用，降级存储
        defaults.set(value, forKey: tokenDefaultsKey)
        return false
    }

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    private func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
