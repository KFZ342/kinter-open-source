import Foundation

/// 账号能力：向小程序暴露当前登录用户的公开信息。
/// 不返回 access token，防止小程序滥用 GitHub API。
final class AccountProvider: CapabilityProvider {
    static var capability: String { "account" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        // 全局开关：用户可以在设置里禁止小程序读取账号
        guard AppSettings.shared.allowAppsAccessAccount else {
            completion(.failure(.permissionDenied("account")))
            return
        }

        switch method {
        case "get":
            guard let user = KinterAuthManager.shared.restoreSession() else {
                completion(.failure(.providerError("未登录")))
                return
            }
            completion(.success([
                "id": user.id,
                "username": user.username,
                "displayName": user.displayName
            ]))

        case "isLoggedIn":
            let loggedIn = KinterAuthManager.shared.restoreSession() != nil
            completion(.success(["loggedIn": loggedIn]))

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
