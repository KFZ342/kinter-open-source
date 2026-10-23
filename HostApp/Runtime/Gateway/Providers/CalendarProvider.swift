import EventKit

final class CalendarProvider: CapabilityProvider {
    static var capability: String { "calendar" }
    static var level: CapabilityLevel { .l1 }
    private let store = EKEventStore()
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.userDenied("calendar"))) }
                return
            }
            switch method {
            case "add":
                let ev = EKEvent(eventStore: self.store)
                ev.title = params["title"] as? String ?? "Event"
                ev.startDate = Date(timeIntervalSince1970: (params["start"] as? Double ?? 0) / 1000)
                ev.endDate = Date(timeIntervalSince1970: (params["end"] as? Double ?? 0) / 1000)
                ev.calendar = self.store.defaultCalendarForNewEvents
                DispatchQueue.main.async {
                    do { try self.store.save(ev, span: .thisEvent); completion(.success(["id": ev.eventIdentifier ?? ""])) }
                    catch { completion(.failure(.providerError(error.localizedDescription))) }
                }
            case "list":
                let start = Date().addingTimeInterval(-86400 * 30)
                let pred = self.store.predicateForEvents(withStart: start, end: Date(), calendars: nil)
                let events = self.store.events(matching: pred).map { ["title": $0.title ?? "", "start": $0.startDate.timeIntervalSince1970 * 1000] }
                DispatchQueue.main.async { completion(.success(["events": events])) }
            default:
                DispatchQueue.main.async { completion(.failure(.methodNotFound(module: Self.capability, method: method))) }
            }
        }
    }
}
