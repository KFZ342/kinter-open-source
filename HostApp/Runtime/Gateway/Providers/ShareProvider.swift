import UIKit

final class ShareProvider: CapabilityProvider {
    static var capability: String { "share" }
    static var level: CapabilityLevel { .l0 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "text" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let text = params["text"] as? String else {
            completion(.failure(.invalidParams("text required")))
            return
        }
        DispatchQueue.main.async {
            guard let top = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                .first else {
                completion(.failure(.providerError("no presenter")))
                return
            }
            let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            top.presentSafely(vc, animated: true) {
                completion(.success(["ok": true]))
            }
        }
    }
}
