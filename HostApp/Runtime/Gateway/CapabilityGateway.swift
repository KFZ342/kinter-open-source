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

    /// 只做授权检查，不调用设备 Provider。
    /// 供 Web 控制台使用：能力仍然要过 manifest / 用户禁用 / 恒定拒绝 / 安全模式 / 权限策略，
    /// 检查通过后由浏览器用自己的摄像头、麦克风采集。
    ///
    /// 授权绑定三元组：本网关实例 = 一个会话（WebAppSession / 原生 Runner 各持独立实例），
    /// 调用方身份取自已在宿主侧解析的 manifest.appId（不是前端传入的字符串），能力为 module；
    /// 三者一起参与判定，不会出现“A 会话的授权被 B 会话复用”。
    func authorizeWebNative(module: String, method: String,
                            completion: @escaping (Result<Void, GatewayError>) -> Void) {
        let start = Date()
        func finish(_ r: Result<Void, GatewayError>) {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            switch r {
            case .success:
                audit.record(module: module, method: method,
                             result: .success(["webNative": true, "source": "web"]), durationMs: ms)
            case .failure(let err):
                audit.record(module: module, method: method,
                             result: .failure(err), durationMs: ms)
            }
            completion(r)
        }

        guard let manifest = currentManifest else {
            return finish(.failure(.unsupported("no manifest loaded")))
        }
        guard manifest.declares(module) else {
            return finish(.failure(.capabilityNotDeclared(module)))
        }
        if disabledCapabilities.contains(module) {
            return finish(.failure(.permissionDenied(module)))
        }
        // 恒定拒绝能力兜底：即使 manifest 误声明 / 注册表被误注册，也不放行。
        if SecurityPolicy.isHardDenied(module) {
            return finish(.failure(.permissionDenied(module)))
        }

        // 与原生小程序走同一套安全模式判定：一次性令牌 / 信任清单 / 组合规则。
        // Web 路径不能绕开用户在宿主横幅里的同意；身份同样取宿主解析的 manifest.appId。
        switch SecurityInterceptor.shared.evaluate(
            module: module, method: method,
            appId: manifest.appId, appName: manifest.name) {
        case .allow:
            break
        case .denyGrantable, .denyHard:
            return finish(.failure(.permissionDenied(module)))
        }

        // Web 原生采集用的是操作者本机的摄像头/麦克风，不是设备能力：
        // 系统权限状态不约束浏览器采集；真正的采集同意由浏览器自己的权限弹窗给出。
        guard let provider = providers[module],
              let level = registry.level(for: module) else {
            return finish(.failure(.unsupported(module)))
        }
        if level == .l3 { return finish(.failure(.unsupported(module))) }

        if let type = type(of: provider) as? RegionSensitiveProvider.Type,
           !type.isAvailableInCurrentRegion() {
            return finish(.failure(.regionUnsupported(module)))
        }

        // 浏览器采集不依赖设备的系统权限（摄像头/麦克风用的是操作者本机），
        // 设备侧的授权状态不应把 Web 原生路径挡住；浏览器会自己弹权限请求。
        if module == "camera" || module == "microphone" {
            return finish(.success(()))
        }

        PermissionPolicy.shared.check(module: module, level: level) { allowed in
            guard allowed else { return finish(.failure(.permissionDenied(module))) }
            finish(.success(()))
        }
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
        // 恒定拒绝能力兜底：不查令牌、不给授权入口，manifest 误声明也不放行。
        if SecurityPolicy.isHardDenied(module) {
            return finish(.failure(.permissionDenied(module)))
        }

        // 安全模式：三级判定（一次性令牌 / 信任清单 / 组合规则，细节见 SecurityInterceptor）。
        // 调用方身份取自已在宿主侧解析的 manifest.appId，不接受前端传入的身份字符串。
        switch SecurityInterceptor.shared.evaluate(
            module: module, method: method,
            appId: manifest.appId, appName: manifest.name) {
        case .allow:
            break
        case .denyGrantable(_, _):
            // 挂起这次调用：用户点「允许本次」后原样重放，不用回小程序再操作一次
            PendingCapabilityStore.shared.park(
                appId: manifest.appId,
                module: module,
                method: method,
                run: { [weak self] in
                    self?.invoke(module: module, method: method,
                                 params: params, completion: completion)
                },
                fail: {
                    finish(.failure(.permissionDenied(module)))
                })
            return
        case .denyHard:
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
