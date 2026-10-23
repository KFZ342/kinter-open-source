import CoreLocation

final class LocationProvider: NSObject, CapabilityProvider, CLLocationManagerDelegate {
    static var capability: String { "location" }
    static var level: CapabilityLevel { .l1 }

    private let manager = CLLocationManager()
    private var completion: ((Result<Any, GatewayError>) -> Void)?

    required override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "getCurrent" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            // 授权结果在 locationManagerDidChangeAuthorization 中处理
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            completion(.failure(.userDenied("location")))
            self.completion = nil
        }
    }

    /// 授权状态变更回调：用户点完系统弹窗后在这里触发定位。
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            completion?(.failure(.userDenied("location")))
            completion = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let payload: [String: Any] = [
            "latitude": loc.coordinate.latitude,
            "longitude": loc.coordinate.longitude,
            "accuracy": loc.horizontalAccuracy
        ]
        completion?(.success(payload))
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(.providerError(error.localizedDescription)))
        completion = nil
    }
}
