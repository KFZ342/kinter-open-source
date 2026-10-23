import UserNotifications

final class NotificationProvider: CapabilityProvider {
    static var capability: String { "notification" }
    static var level: CapabilityLevel { .l1 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "requestPermission":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { ok, err in
                DispatchQueue.main.async {
                    if let err = err { completion(.failure(.providerError(err.localizedDescription))) }
                    else { completion(.success(["granted": ok])) }
                }
            }
        case "schedule":
            let title = params["title"] as? String ?? "Notification"
            let body = params["body"] as? String ?? ""
            let after = params["after"] as? Double ?? 1
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(after, 1), repeats: false)
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req) { err in
                DispatchQueue.main.async {
                    if let err = err { completion(.failure(.providerError(err.localizedDescription))) }
                    else { completion(.success(["ok": true])) }
                }
            }
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
