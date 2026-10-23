import UIKit
import AudioToolbox

final class VibrateProvider: CapabilityProvider {
    static var capability: String { "vibrate" }
    static var level: CapabilityLevel { .l0 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "short" || method == "long" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        DispatchQueue.main.async {
            if method == "long" {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            } else {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
            }
            completion(.success(["ok": true]))
        }
    }
}
