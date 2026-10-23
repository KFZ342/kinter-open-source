import UIKit

final class DeviceInfoProvider: CapabilityProvider {
    static var capability: String { "deviceInfo" }
    static var level: CapabilityLevel { .l0 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "get" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        let d = UIDevice.current
        let screen = UIScreen.main
        let info: [String: Any] = [
            "model": d.model,
            "systemName": d.systemName,
            "systemVersion": d.systemVersion,
            "name": d.name,
            "vendorId": d.identifierForVendor?.uuidString ?? "",
            "screenWidth": Int(screen.bounds.width),
            "screenHeight": Int(screen.bounds.height),
            "scale": screen.scale
        ]
        completion(.success(info))
    }
}
