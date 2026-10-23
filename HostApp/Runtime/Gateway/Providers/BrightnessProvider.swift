import UIKit

final class BrightnessProvider: CapabilityProvider {
    static var capability: String { "brightness" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "get":
            completion(.success(["value": UIScreen.main.brightness]))
        case "set":
            let v = params["value"] as? CGFloat ?? -1
            guard v >= 0 && v <= 1 else {
                completion(.failure(.invalidParams("value 需在 0-1 之间")))
                return
            }
            DispatchQueue.main.async {
                UIScreen.main.brightness = v
                completion(.success(["value": v]))
            }
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
