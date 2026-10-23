import HealthKit

final class HealthProvider: CapabilityProvider {
    static var capability: String { "health" }
    static var level: CapabilityLevel { .l2 }
    private let store = HKHealthStore()
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(.unsupported("health")))
            return
        }
        guard method == "stepCount",
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        // HealthKit 在缺少 entitlement 时会抛 ObjC 异常，Swift 无法 catch，
        // 必须经 ObjC 捕获器隔离，否则整个 App 崩溃。
        var thrown: String?
        thrown = ObjCExceptionCatcher.catchException {
            self.store.requestAuthorization(toShare: [], read: [steps]) { ok, _ in
                guard ok else {
                    DispatchQueue.main.async { completion(.failure(.userDenied("health"))) }
                    return
                }
                let start = Calendar.current.startOfDay(for: Date())
                let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
                let q = HKStatisticsQuery(quantityType: steps, quantitySamplePredicate: pred, options: .cumulativeSum) { _, res, _ in
                    let sum = res?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    DispatchQueue.main.async { completion(.success(["steps": Int(sum)])) }
                }
                self.store.execute(q)
            }
        }
        if thrown != nil {
            completion(.failure(.unsupported("health")))
        }
    }
}
