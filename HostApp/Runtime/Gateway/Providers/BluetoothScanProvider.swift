import CoreBluetooth

final class BluetoothScanProvider: NSObject, CapabilityProvider, CBCentralManagerDelegate {
    static var capability: String { "bluetoothScan" }
    static var level: CapabilityLevel { .l1 }
    required override init() { super.init() }

    private var manager: CBCentralManager?
    private var completion: ((Result<Any, GatewayError>) -> Void)?
    private var discovered: [String: [String: Any]] = [:]

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "scan" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        let duration = params["duration"] as? TimeInterval ?? 5
        self.completion = completion
        self.discovered = [:]
        self.manager = CBCentralManager(delegate: self, queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, let c = self.completion else { return }
            self.manager?.stopScan()
            c(.success(["devices": Array(self.discovered.values)]))
            self.completion = nil
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        case .unsupported:
            completion?(.failure(.unsupported("bluetooth")))
            completion = nil
        case .unauthorized:
            completion?(.failure(.userDenied("bluetooth")))
            completion = nil
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier.uuidString
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "未知设备"
        discovered[id] = [
            "id": id,
            "name": name,
            "rssi": RSSI.intValue
        ]
    }
}
