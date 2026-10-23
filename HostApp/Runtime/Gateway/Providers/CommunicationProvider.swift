import UIKit

final class CommunicationProvider: CapabilityProvider {
    static var capability: String { "communication" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let urlString: String?
        switch method {
        case "call":
            guard let phone = params["phone"] as? String else {
                completion(.failure(.invalidParams("phone 必填")))
                return
            }
            let cleaned = phone.replacingOccurrences(of: " ", with: "")
            urlString = "tel://\(cleaned)"
        case "sms":
            guard let phone = params["phone"] as? String else {
                completion(.failure(.invalidParams("phone 必填")))
                return
            }
            urlString = "sms://\(phone)"
        case "mail":
            guard let to = params["to"] as? String else {
                completion(.failure(.invalidParams("to 必填")))
                return
            }
            urlString = "mailto:\(to)"
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let s = urlString, let url = URL(string: s) else {
            completion(.failure(.invalidParams("URL 无效")))
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { ok in
                if ok { completion(.success(["ok": true])) }
                else { completion(.failure(.providerError("无法打开"))) }
            }
        }
    }
}
