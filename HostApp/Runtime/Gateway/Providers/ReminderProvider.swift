import EventKit

final class ReminderProvider: CapabilityProvider {
    static var capability: String { "reminder" }
    static var level: CapabilityLevel { .l1 }

    private let store = EKEventStore()
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        store.requestFullAccessToReminders { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.userDenied("reminder"))) }
                return
            }
            guard method == "add" else {
                DispatchQueue.main.async { completion(.failure(.methodNotFound(module: Self.capability, method: method))) }
                return
            }
            guard let cal = self.store.defaultCalendarForNewReminders() else {
                DispatchQueue.main.async { completion(.failure(.providerError("no default calendar"))) }
                return
            }
            let r = EKReminder(eventStore: self.store)
            r.title = params["title"] as? String ?? "Reminder"
            r.calendar = cal
            do {
                try self.store.save(r, commit: true)
                DispatchQueue.main.async { completion(.success(["ok": true, "id": r.calendarItemIdentifier])) }
            } catch {
                DispatchQueue.main.async { completion(.failure(.providerError(error.localizedDescription))) }
            }
        }
    }
}
