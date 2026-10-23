import CoreLocation

final class LocationWatchProvider: NSObject, CapabilityProvider, CLLocationManagerDelegate {
    static var capability: String { "locationWatch" }
    static var level: CapabilityLevel { .l1 }

    private let manager = CLLocationManager()
    private var completion: ((Result<Any, GatewayError>) -> Void)?
    private var isWatching = false
    private var accumulated: [CLLocation] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "start":
            self.completion = completion
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                isWatching = true
                accumulated = []
                manager.startUpdatingLocation()
                completion(.success(["ok": true, "watching": true]))
            default:
                completion(.failure(.userDenied("location")))
            }
        case "stop":
            isWatching = false
            manager.stopUpdatingLocation()
            completion(.success(["ok": true, "points": accumulated.count]))
        case "isWatching":
            completion(.success(["watching": isWatching]))
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let c = completion, !isWatching else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isWatching = true
            accumulated = []
            manager.startUpdatingLocation()
            c(.success(["ok": true, "watching": true]))
            completion = nil
        case .denied, .restricted:
            c(.failure(.userDenied("location")))
            completion = nil
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        accumulated.append(contentsOf: locations)
        if accumulated.count > 100 { accumulated.removeFirst(accumulated.count - 100) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if isWatching { return }
        completion?(.failure(.providerError(error.localizedDescription)))
        completion = nil
    }
}
