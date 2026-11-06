import Foundation

/// 安全模式拦截器。
/// 三级判定：critical 默认拒（可允许本次）/ standard 默认拒（可允许本次、可信任）/ network 默认放行只记录。
/// 组合规则：高危能力之后短时间内出现外发，升级为告警。
final class SecurityInterceptor {
    static let shared = SecurityInterceptor()
    private init() {}

    enum Decision {
        /// 放行
        case allow
        /// 拦截，用户可点「允许本次」或「以后都允许」
        case denyGrantable(module: String)
        /// 拦截，不可放行（恒定拒绝的能力）
        case denyHard(module: String)
    }

    /// 组合规则的观察窗口（秒）
    private let comboWindow: TimeInterval = 5
    /// 最近一次高危能力调用时间（按 appId 记）
    private var lastCriticalAt: [String: Date] = [:]
    private let lock = NSLock()

    func evaluate(module: String, method: String, appId: String?, appName: String?) -> Decision {
        guard SecurityMode.shared.isEnabled else { return .allow }

        // 恒定拒绝：不查令牌、不给授权入口
        if SecurityPolicy.isHardDenied(module) {
            TraceRecorder.shared.record(module: module, method: method,
                                        status: "blocked", appId: appId)
            postEvent(module: module, method: method, appId: appId, appName: appName)
            return .denyHard(module: module)
        }

        // 非敏感能力：放行，记录
        guard let tier = SecurityPolicy.tier(of: module) else {
            TraceRecorder.shared.record(module: module, method: method,
                                        status: "ok", appId: appId)
            return .allow
        }

        // ---- 组合规则：高危能力之后 5 秒内外发 ----
        if tier == .network {
            let key = appId ?? "-"
            lock.lock()
            let recent = lastCriticalAt[key].map { Date().timeIntervalSince($0) <= comboWindow } ?? false
            lock.unlock()
            if recent {
                TraceRecorder.shared.record(module: module, method: method,
                                            status: "blocked", appId: appId)
                postEvent(module: module, method: method, appId: appId, appName: appName)
                return .denyGrantable(module: module)
            }
        }

        // 先记时间点：无论最终放行还是被拦，都算"刚发生过高危调用"
        if tier == .critical {
            let key = appId ?? "-"
            lock.lock(); lastCriticalAt[key] = Date(); lock.unlock()
        }

        // 一次性令牌（用户点了「允许本次」）
        if OneShotGrant.shared.consume(module: module, appId: appId) {
            TraceRecorder.shared.record(module: module, method: method,
                                        status: "ok", appId: appId)
            NotificationCenter.default.post(name: .securityCapabilityGranted,
                                            object: SecurityEvent(module: module, method: method,
                                                                  appId: appId, appName: appName,
                                                                  timestamp: Date()))
            return .allow
        }

        // 信任清单只对 standard 生效；critical 永远不给永久信任
        if tier == .standard, let id = appId,
           TrustedCapabilities.shared.isTrusted(appId: id, module: module) {
            TraceRecorder.shared.record(module: module, method: method,
                                        status: "ok", appId: appId)
            return .allow
        }

        // 其余一律拦截，并给用户一个授权入口
        TraceRecorder.shared.record(module: module, method: method,
                                    status: "blocked", appId: appId)
        postEvent(module: module, method: method, appId: appId, appName: appName)
        return .denyGrantable(module: module)
    }

    private func postEvent(module: String, method: String, appId: String?, appName: String?) {
        let event = SecurityEvent(module: module, method: method,
                                  appId: appId, appName: appName, timestamp: Date())
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .securityCapabilityBlocked, object: event)
        }
    }
}
