import UIKit

/// 打开外部链接 / 原生 App（URL Scheme）。
/// - open: 打开 http/https 链接或自定义 scheme 唤起原生 App（如 weixin://、kinter://）
/// - canOpen: 查询 scheme 是否能被系统打开（App 是否已安装）
final class OpenURLProvider: CapabilityProvider {
    static var capability: String { "openURL" }
    static var level: CapabilityLevel { .l0 }

    required init() {}

    /// 危险 scheme 黑名单：禁止宿主被 JS 拿去打开本地文件或执行脚本
    private static let forbiddenSchemes: Set<String> = ["file", "javascript", "data", "vbscript", "about"]

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "open":
            guard let s = params["url"] as? String, let u = URL(string: s) else {
                completion(.failure(.invalidParams("url required")))
                return
            }
            guard Self.isSafeScheme(u.scheme) else {
                completion(.failure(.providerError("不允许的 URL Scheme: \(u.scheme ?? "未知")")))
                return
            }
            DispatchQueue.main.async {
                if !UIApplication.shared.canOpenURL(u) {
                    completion(.failure(.providerError("无法打开：App 未安装或 scheme 不受支持")))
                    return
                }
                UIApplication.shared.open(u, options: [:]) { ok in
                    ok ? completion(.success(["ok": true])) : completion(.failure(.providerError("cannot open")))
                }
            }

        case "canOpen":
            guard let s = params["url"] as? String, let u = URL(string: s) else {
                completion(.failure(.invalidParams("url required")))
                return
            }
            DispatchQueue.main.async {
                completion(.success(["canOpen": UIApplication.shared.canOpenURL(u)]))
            }

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    /// 仅允许 http/https 与自定义 scheme；禁止 file/javascript/data/vbscript/about
    private static func isSafeScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased(), !scheme.isEmpty else { return false }
        return !forbiddenSchemes.contains(scheme)
    }
}
