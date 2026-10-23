import Foundation
import Security

/// 认证凭据的持久化存储。
/// token 优先存 Keychain；如果 Keychain 不可用（如未签名构建），降级到 UserDefaults。
/// 用户信息缓存存 UserDefaults。
final class AuthStore {
    static let shared = AuthStore()

    private let tokenService = "com.kinter.auth.token"
    private let tokenAccount = "kinter_access_token"
    private let userKey = "auth.cachedUser"
    private let fallbackTokenKey = "auth.fallbackToken"
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Token

    var accessToken: String? {
        get {
            if let kc = readKeychain() { return kc }
            return defaults.string(forKey: fallbackTokenKey)
        }
        set {
            if let value = newValue {
                let kcStatus = writeKeychain(value)
                if kcStatus != errSecSuccess {
                    // Keychain 不可用，降级到 UserDefaults
                    defaults.set(value, forKey: fallbackTokenKey)
                    NSLog("[AuthStore] keychain unavailable (%d), fallback to UserDefaults", kcStatus)
                } else {
                    // Keychain 成功，清掉旧的 fallback
                    defaults.removeObject(forKey: fallbackTokenKey)
                }
            } else {
                deleteKeychain()
                defaults.removeObject(forKey: fallbackTokenKey)
            }
        }
    }

    // MARK: - 用户信息缓存

    var cachedUser: KinterUser? {
        get {
            guard let data = defaults.data(forKey: userKey) else { return nil }
            return try? JSONDecoder().decode(KinterUser.self, from: data)
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: userKey)
            } else {
                defaults.removeObject(forKey: userKey)
            }
        }
    }

    /// 清空所有凭据
    func clear() {
        accessToken = nil
        cachedUser = nil
    }

    // MARK: - Keychain

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

    @discardableResult
    private func writeKeychain(_ value: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil)
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
