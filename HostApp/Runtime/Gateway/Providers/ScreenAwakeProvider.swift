import UIKit

final class ScreenAwakeProvider: CapabilityProvider {
    static var capability: String { "screenAwake" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "enable":
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = true
                completion(.success(["ok": true]))
            }
        case "disable":
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
                completion(.success(["ok": true]))
            }
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
