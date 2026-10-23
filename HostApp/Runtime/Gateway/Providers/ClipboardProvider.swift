import UIKit

final class ClipboardProvider: CapabilityProvider {
    static var capability: String { "clipboard" }
    static var level: CapabilityLevel { .l0 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        DispatchQueue.main.async {
            switch method {
            case "set":
                guard let text = params["data"] as? String else {
                    completion(.failure(.invalidParams("data required")))
                    return
                }
                UIPasteboard.general.string = text
                completion(.success(["ok": true]))
            case "get":
                let text = UIPasteboard.general.string ?? ""
                completion(.success(["data": text]))
            default:
                completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            }
        }
    }
}
