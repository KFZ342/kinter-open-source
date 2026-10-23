import Foundation

/// Kinter 账号认证管理器。
/// 对接自建服务器 /api/register、/api/login、/api/me、/api/logout。
final class KinterAuthManager {
    static let shared = KinterAuthManager()
    private init() {}

    /// 默认服务器地址（开源版为空）。
    /// 账号登录、应用发布与商店订阅需要自建服务器（接口契约见 docs/），
    /// 构建后在「设置 → 账号 → 认证服务器」填入你的服务器地址。
    static let defaultServerURL = ""

    enum AuthError: LocalizedError {
        case notConfigured
        case invalidCredentials
        case usernameTaken
        case invalidUsername
        case weakPassword
        case networkError(Error)
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:        return "未配置认证服务器"
            case .invalidCredentials:   return "用户名或密码错误"
            case .usernameTaken:        return "用户名已被占用"
            case .invalidUsername:      return "用户名需 4-32 位，只能包含字母、数字和下划线"
            case .weakPassword:         return "密码至少 8 位"
            case .networkError(let e):  return e.localizedDescription
            case .serverError(let s):   return s
            }
        }
    }

    private var baseURL: URL? {
        let raw = AppSettings.shared.authServerURL ?? Self.defaultServerURL
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed)
    }

    var isConfigured: Bool { baseURL != nil }

    // MARK: - 登录

    func login(username: String, password: String,
               completion: @escaping (Result<KinterUser, Error>) -> Void) {
        post(
            path: "/api/login",
            body: ["username": username, "password": password],
            completion: completion
        )
    }

    // MARK: - 注册

    func register(username: String, password: String, name: String,
                  completion: @escaping (Result<KinterUser, Error>) -> Void) {
        post(
            path: "/api/register",
            body: ["username": username, "password": password, "name": name],
            completion: completion
        )
    }

    // MARK: - 登出

    func logout() {
        guard let token = AuthStore.shared.accessToken,
              let base = baseURL else {
            AuthStore.shared.clear()
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("/api/logout"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        // 不等结果，本地立即清空
        AuthStore.shared.clear()
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - 恢复登录态

    /// 有 token 且能拉到 /api/me 才算已登录。
    /// 同步返回缓存用户，异步验证 token 是否还有效。
    func restoreSession() -> KinterUser? {
        guard AuthStore.shared.accessToken != nil else { return nil }
        return AuthStore.shared.cachedUser
    }

    /// 主动验证 token。失败时清空本地凭据。
    func validate(completion: @escaping (Bool) -> Void) {
        guard let token = AuthStore.shared.accessToken,
              let base = baseURL else {
            completion(false)
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("/api/me"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                // 网络错误：保留本地凭据，只是暂时验证不了
                if err != nil {
                    NSLog("[Auth] validate network error, keep session")
                    completion(true)
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    completion(true)
                    return
                }
                // 401：token 无效，清掉
                if http.statusCode == 401 {
                    NSLog("[Auth] validate 401, clearing")
                    AuthStore.shared.clear()
                    completion(false)
                    return
                }
                // 200：解码
                if http.statusCode == 200,
                   let data = data,
                   let user = try? JSONDecoder().decode(KinterUser.self, from: data) {
                    AuthStore.shared.cachedUser = user
                    completion(true)
                    return
                }
                // 其他状态码：保留
                completion(true)
            }
        }.resume()
    }

    // MARK: - 内部

    private func post(path: String, body: [String: Any],
                      completion: @escaping (Result<KinterUser, Error>) -> Void) {
        guard let base = baseURL else {
            completion(.failure(AuthError.notConfigured))
            return
        }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(AuthError.networkError(err)))
                    return
                }
                let http = resp as? HTTPURLResponse
                let code = http?.statusCode ?? 0
                let data = data ?? Data()

                if (200...299).contains(code) {
                    do {
                        let wrapper = try JSONDecoder().decode(LoginResponse.self, from: data)
                        AuthStore.shared.accessToken = wrapper.token
                        AuthStore.shared.cachedUser = wrapper.user
                        completion(.success(wrapper.user))
                    } catch {
                        completion(.failure(AuthError.serverError("响应解析失败")))
                    }
                    return
                }

                // 错误分支
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errCode = json["error"] as? String {
                    switch errCode {
                    case "invalid_credentials":
                        completion(.failure(AuthError.invalidCredentials))
                    case "username_taken":
                        completion(.failure(AuthError.usernameTaken))
                    case "invalid_username":
                        completion(.failure(AuthError.invalidUsername))
                    case "invalid_password", "weak_password":
                        completion(.failure(AuthError.weakPassword))
                    default:
                        completion(.failure(AuthError.serverError(errCode)))
                    }
                } else {
                    completion(.failure(AuthError.serverError("HTTP \(code)")))
                }
            }
        }.resume()
    }

    private struct LoginResponse: Codable {
        let token: String
        let user: KinterUser
    }
}
