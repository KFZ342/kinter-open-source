import CoreBluetooth

final class BluetoothProvider: NSObject, CapabilityProvider, CBCentralManagerDelegate {
    static var capability: String { "bluetooth" }
    static var level: CapabilityLevel { .l1 }

    private var manager: CBCentralManager?
    private var completion: ((Result<Any, GatewayError>) -> Void)?

    required override init() { super.init() }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "scan" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        self.completion = completion
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: String
        switch central.state {
        case .poweredOn:      state = "poweredOn"
        case .poweredOff:     state = "poweredOff"
        case .unauthorized:   state = "unauthorized"
        case .unsupported:    state = "unsupported"
        case .resetting:      state = "resetting"
        default:              state = "unknown"
        }

        switch central.state {
        case .poweredOn:
            completion?(.success(["state": state, "ready": true]))
        case .unauthorized:
            completion?(.failure(.userDenied("bluetooth")))
        case .unsupported:
            // 模拟器无蓝牙硬件——这是环境不支持，不是错误
            completion?(.failure(.unsupported("bluetooth")))
        default:
            completion?(.success(["state": state, "ready": false]))
        }
        completion = nil
    }
}
