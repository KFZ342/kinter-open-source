import LocalAuthentication

final class BiometricProvider: CapabilityProvider {
    static var capability: String { "biometric" }
    static var level: CapabilityLevel { .l1 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "authenticate" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }

        #if targetEnvironment(simulator)
        // 模拟器的 CoreAuthUI 组件自身有 bug（UIResponder doesNotRecognizeSelector），
        // 一旦触发 Face ID 验证界面就会崩溃。这里直接拒绝，避免拉起系统组件。
        completion(.failure(.unsupported("biometric (simulator)")))
        return
        #else
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            completion(.failure(.unsupported("biometric")))
            return
        }
        let reason = params["reason"] as? String ?? "验证身份"
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, err in
            DispatchQueue.main.async {
                if ok {
                    completion(.success(["ok": true]))
                } else if let e = err as NSError?, e.code == LAError.userCancel.rawValue {
                    completion(.failure(.userDenied("biometric")))
                } else {
                    completion(.failure(.userDenied("biometric")))
                }
            }
        }
        #endif
    }
}
