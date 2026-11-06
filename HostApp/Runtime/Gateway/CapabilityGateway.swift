import Foundation

final class CapabilityGateway {
    /// 每个小程序会话持有独立实例，避免多任务互相覆盖权限状态。
    private let registry = CapabilityRegistry.shared
    private let audit = AuditLog.shared
    /// 本会话独立的 Provider 实例
    private let providers: [String: CapabilityProvider]
    /// 本会话的启动参数
    var launchParams: [String: Any]?
    private var currentManifest: MiniAppManifest?
    /// 当前小程序被用户禁用的能力集合
    private var disabledCapabilities: Set<String> = []

    init() {
        self.providers = registry.makeFreshProviders()
    }

    func setManifest(_ m: MiniAppManifest) { currentManifest = m }

    func setDisabledCapabilities(_ set: Set<String>) { disabledCapabilities = set }

    /// 绑定事件推送。每次 WebView 创建后调用一次。
    func bindEmitters(_ emit: @escaping (String, Any) -> Void) {
        (providers["websocket"] as? WebSocketProvider)?.emitter = emit
        (providers["networkWatch"] as? NetworkWatchProvider)?.emitter = emit
    }

    func invoke(module: String, method: String, params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let start = Date()
        func finish(_ r: Result<Any, GatewayError>) {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            self.audit.record(module: module, method: method, result: r, durationMs: ms)
            completion(r)
        }

        guard let manifest = currentManifest else {
            return finish(.failure(.unsupported("no manifest loaded")))
        }
        guard manifest.declares(module) else {
            return finish(.failure(.capabilityNotDeclared(module)))
        }
        // 用户手动禁用
        if disabledCapabilities.contains(module) {
            return finish(.failure(.permissionDenied(module)))
        }

        // 安全模式：三级判定（策略细节见 SecurityInterceptor）
        switch SecurityInterceptor.shared.evaluate(
            module: module, method: method,
            appId: manifest.appId, appName: manifest.name) {
        case .allow:
            break
        case .denyGrantable, .denyHard:
            return finish(.failure(.permissionDenied(module)))
        }

        guard let provider = providers[module],
              let level = registry.level(for: module) else {
            return finish(.failure(.unsupported(module)))
        }
        if level == .l3 { return finish(.failure(.unsupported(module))) }

        if let type = type(of: provider) as? RegionSensitiveProvider.Type,
           !type.isAvailableInCurrentRegion() {
            return finish(.failure(.regionUnsupported(module)))
        }

        PermissionPolicy.shared.check(module: module, level: level) { allowed in
            guard allowed else { return finish(.failure(.permissionDenied(module))) }

            // 需要知道调用方 appId 的能力，统一走协议注入
            if let injectable = provider as? AppContextInjectable {
                injectable.appId = manifest.appId
            }

            // once 语义：provider 可能先回调再抛异常，避免上层收到两次结果
            var didFinish = false
            let once: (Result<Any, GatewayError>) -> Void = { r in
                guard !didFinish else { return }
                didFinish = true
                finish(r)
            }
            let thrown = ObjCExceptionCatcher.catchException {
                provider.invoke(method: method, params: params) { result in
                    once(result)
                }
            }
            if let t = thrown, !didFinish {
                once(.failure(.providerError("exception: \(t)")))
            }
        }
    }
}
