import CoreSpotlight
import UniformTypeIdentifiers

/// 系统搜索能力：把小程序内容索引到 Spotlight。
/// 用户可以在系统搜索里搜到，点击后通过 NSUserActivity 深链回小程序。
final class SpotlightProvider: CapabilityProvider, AppContextInjectable {
    static var capability: String { "spotlight" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    /// 当前调用方 appId，由网关注入。
    var appId: String?

    func invoke(method: String, params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "index":
            index(params: params, completion: completion)
        case "remove":
            remove(params: params, completion: completion)
        case "removeAll":
            removeAll(completion: completion)
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    private func index(params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let id = params["id"] as? String, !id.isEmpty else {
            completion(.failure(.invalidParams("id 必填"))); return
        }
        guard let title = params["title"] as? String, !title.isEmpty else {
            completion(.failure(.invalidParams("title 必填"))); return
        }
        let domain = "com.kinter.miniapp.\(appId ?? "unknown")"

        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = title
        attrs.contentDescription = params["description"] as? String
        attrs.keywords = params["keywords"] as? [String] ?? []

        let item = CSSearchableItem(
            uniqueIdentifier: "\(domain):\(id)",
            domainIdentifier: domain,
            attributeSet: attrs
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(.providerError(err.localizedDescription)))
                } else {
                    completion(.success(["ok": true, "id": id]))
                }
            }
        }
    }

    private func remove(params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let id = params["id"] as? String, !id.isEmpty else {
            completion(.failure(.invalidParams("id 必填"))); return
        }
        let domain = "com.kinter.miniapp.\(appId ?? "unknown")"
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ["\(domain):\(id)"]) { err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(.providerError(err.localizedDescription)))
                } else {
                    completion(.success(["ok": true]))
                }
            }
        }
    }

    private func removeAll(completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let domain = "com.kinter.miniapp.\(appId ?? "unknown")"
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(.providerError(err.localizedDescription)))
                } else {
                    completion(.success(["ok": true]))
                }
            }
        }
    }
}
