import UIKit

final class OpenURLProvider: CapabilityProvider {
    static var capability: String { "openURL" }
    static var level: CapabilityLevel { .l0 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "open", let s = params["url"] as? String, let u = URL(string: s) else {
            completion(.failure(.invalidParams("url required")))
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(u, options: [:]) { ok in
                ok ? completion(.success(["ok": true])) : completion(.failure(.providerError("cannot open")))
            }
        }
    }
}
