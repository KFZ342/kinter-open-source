import Foundation

final class StorageProvider: CapabilityProvider {
    static var capability: String { "storage" }
    static var level: CapabilityLevel { .l0 }

    private let defaults = UserDefaults.standard
    private let prefix = "miniapp.storage."

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let key = params["key"] as? String, !key.isEmpty else {
            completion(.failure(.invalidParams("key required")))
            return
        }
        let fullKey = prefix + key

        switch method {
        case "set":
            guard let value = params["data"] else {
                completion(.failure(.invalidParams("data required")))
                return
            }
            // 单键上限 256KB，防止单个小程序写爆 UserDefaults
            let encoded = (try? JSONSerialization.data(withJSONObject: value))?.count ?? 0
            guard encoded <= 256 * 1024 else {
                completion(.failure(.invalidParams("value too large (>256KB)")))
                return
            }
            defaults.set(value, forKey: fullKey)
            completion(.success(["ok": true]))
        case "get":
            let value = defaults.object(forKey: fullKey)
            completion(.success(["data": value ?? NSNull()]))
        case "remove":
            defaults.removeObject(forKey: fullKey)
            completion(.success(["ok": true]))
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
