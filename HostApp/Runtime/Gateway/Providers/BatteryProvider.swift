import UIKit

final class BatteryProvider: CapabilityProvider {
    static var capability: String { "battery" }
    static var level: CapabilityLevel { .l0 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "get" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        var state = "unknown"
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        default: state = "unknown"
        }
        completion(.success(["level": level < 0 ? 0.0 : level, "state": state]))
    }
}
