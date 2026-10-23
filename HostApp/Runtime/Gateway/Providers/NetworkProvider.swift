import Network

final class NetworkProvider: CapabilityProvider {
    static var capability: String { "network" }
    static var level: CapabilityLevel { .l0 }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.monitor")
    private var current: NWPath?

    required init() {
        monitor.pathUpdateHandler = { [weak self] p in self?.current = p }
        monitor.start(queue: queue)
    }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "get" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        queue.async {
            guard let p = self.current else {
                completion(.success(["status": "unknown"]))
                return
            }
            var status = "offline"
            if p.status == .satisfied {
                if p.usesInterfaceType(.wifi) { status = "wifi" }
                else if p.usesInterfaceType(.cellular) { status = "cellular" }
                else if p.usesInterfaceType(.wiredEthernet) { status = "ethernet" }
                else { status = "other" }
            }
            completion(.success(["status": status, "expensive": p.isExpensive]))
        }
    }
}
