import CoreMotion

final class MotionProvider: CapabilityProvider {
    static var capability: String { "motion" }
    static var level: CapabilityLevel { .l1 }

    private let motion = CMMotionManager()
    private var completion: ((Result<Any, GatewayError>) -> Void)?
    private var finished = false

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "deviceMotion" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard motion.isDeviceMotionAvailable else {
            completion(.failure(.unsupported("设备不支持运动传感器")))
            return
        }

        self.completion = completion
        self.finished = false

        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            guard let self = self, !self.finished else { return }
            if let error = error {
                self.finish(.failure(.providerError("运动传感器: \(error.localizedDescription)")))
                return
            }
            guard let d = data else { return }
            self.finish(.success([
                "pitch": d.attitude.pitch,
                "roll": d.attitude.roll,
                "yaw": d.attitude.yaw,
                "gravityX": d.gravity.x,
                "gravityY": d.gravity.y,
                "gravityZ": d.gravity.z,
                "accelerationX": d.userAcceleration.x,
                "accelerationY": d.userAcceleration.y,
                "accelerationZ": d.userAcceleration.z
            ]))
        }

        // 3 秒超时
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, !self.finished else { return }
            self.finish(.failure(.unsupported("运动传感器无响应，可能未授权或在模拟器中不可用")))
        }
    }

    private func finish(_ result: Result<Any, GatewayError>) {
        guard !finished else { return }
        finished = true
        motion.stopDeviceMotionUpdates()
        completion?(result)
        completion = nil
    }
}
