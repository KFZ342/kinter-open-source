import Foundation
import Security

/// 第三方 AI 模型配置。持久化到 UserDefaults。
/// 支持任意 OpenAI 兼容接口（OpenAI / DeepSeek / 智谱 / 通义 / 本地 Ollama 等）。
/// API Key 优先存 Keychain；Keychain 不可用（如未签名构建）时降级 UserDefaults。
final class AISettings {
    static let shared = AISettings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let endpoint = "ai.endpoint"
        static let apiKey   = "ai.apiKey"
        static let model    = "ai.model"
        static let temperature = "ai.temperature"
        static let timeout  = "ai.timeout"
    }

    /// Keychain 中存 API Key 的服务名（与认证 token 分开）
    private let keychainService = "com.kinter.ai.apikey"
    private let keychainAccount = "kinter_ai_api_key"

    private init() {}

    /// 接口地址。形如 https://api.openai.com/v1/chat/completions
    /// 也接受只填 https://api.openai.com/v1，自动补 /chat/completions
    var endpoint: String {
        get { defaults.string(forKey: Key.endpoint) ?? "" }
        set { defaults.set(newValue, forKey: Key.endpoint) }
    }

    var apiKey: String {
        get {
            if let kc = readKeychain() { return kc }
            // 兼容旧版本：曾明文存在 UserDefaults
            return defaults.string(forKey: Key.apiKey) ?? ""
        }
        set {
            // newValue 是非 Optional 的 String，直接判断空
            let value = newValue
            if !value.isEmpty {
                if writeKeychain(value) != errSecSuccess {
                    // Keychain 不可用，降级到 UserDefaults 并提示
                    defaults.set(value, forKey: Key.apiKey)
                    NSLog("[AISettings] keychain unavailable, fallback to UserDefaults")
                } else {
                    // Keychain 成功，清掉旧的明文
                    defaults.removeObject(forKey: Key.apiKey)
                }
            } else {
                deleteKeychain()
                defaults.removeObject(forKey: Key.apiKey)
            }
        }
    }

    var model: String {
        get { defaults.string(forKey: Key.model) ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    var temperature: Double {
        get {
            let v = defaults.double(forKey: Key.temperature)
            return v == 0 ? 0.7 : v
        }
        set { defaults.set(newValue, forKey: Key.temperature) }
    }

    /// 请求超时（秒）。AI 生成可能较慢，默认 120 秒。
    var timeout: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.timeout)
            return v == 0 ? 120 : v
        }
        set { defaults.set(newValue, forKey: Key.timeout) }
    }

    var isConfigured: Bool {
        !endpoint.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    /// 补全完整 URL：用户只填到 /v1 时自动加 /chat/completions
    var resolvedEndpoint: URL? {
        var s = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasSuffix("/v1") { s += "/chat/completions" }
        return URL(string: s)
    }

    // MARK: - Keychain

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    @discardableResult
    private func writeKeychain(_ value: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
