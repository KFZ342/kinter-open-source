import Foundation
import Network

/// 网络状态持续监听。状态变化通过事件推送：network.change { status, expensive }
final class NetworkWatchProvider: CapabilityProvider {
    static var capability: String { "networkWatch" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.watch")
    private var started = false
    private var lastStatus: String = "unknown"

    /// 由 Runner 注入
    var emitter: ((String, Any) -> Void)?

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "start":
            if started {
                completion(.success(["ok": true, "already": true]))
                return
            }
            started = true
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self = self else { return }
                var status = "offline"
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) { status = "wifi" }
                    else if path.usesInterfaceType(.cellular) { status = "cellular" }
                    else if path.usesInterfaceType(.wiredEthernet) { status = "ethernet" }
                    else { status = "other" }
                }
                // 只在状态变化时推送
                guard status != self.lastStatus else { return }
                self.lastStatus = status
                self.emitter?("network.change", [
                    "status": status,
                    "expensive": path.isExpensive
                ])
            }
            monitor.start(queue: queue)
            completion(.success(["ok": true]))

        case "stop":
            monitor.cancel()
            started = false
            completion(.success(["ok": true]))

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
