import Foundation

/// 安全模式拦截器。
/// 四档判定：critical 默认拒（只允许本次）/ standard 默认拒（可允许本次、可信任）/
/// network 默认放行但记录、与隐私数据组合出现时拦下 / benign 只记录。
final class SecurityInterceptor {
    static let shared = SecurityInterceptor()
    private init() {}

    enum Decision {
        /// 放行
        case allow
        /// 拦截，用户可点「允许本次」或「以后都允许」
        case denyGrantable(module: String, reason: String?)
        /// 拦截，不可放行（恒定拒绝的能力）
        case denyHard(module: String)
    }

    /// 最近一次「隐私数据类」能力调用：appId -> (能力, 时间)。
    /// 组合规则靠它判断"刚读完敏感数据就往外发"。
    private struct Touch {
        let module: String
        let at: Date
    }
    private var touches: [String: Touch] = [:]
    private let lock = NSLock()

    func evaluate(module: String, method: String, appId: String?, appName: String?) -> Decision {
        guard SecurityMode.shared.isEnabled else { return .allow }

        // 恒定拒绝：不查令牌、不给授权入口
        if SecurityPolicy.isHardDenied(module) {
            TraceRecorder.shared.record(module: module, method: method,
                                        status: "blocked", appId: appId)
            postEvent(module: module, method: method, appId: appId, appName: appName, reason: nil)
            return .denyHard(module: module)
        }

        // 直通模块（router/store/auth/app/popup/permission）没有分级，
        // 它们的危险方法在桥接层单独把关，这里只记录
        guard let tier = SecurityPolicy.tier(of: module) else {
            TraceRecorder.shared.record(module: module, method: method,
                                        status: "ok", appId: appId)
            return .allow
        }

        // 低敏：只记录，不打扰
        if tier == .benign {
            TraceRecorder.shared.record(module: module, method: method,
                                        status: "ok", appId: appId)
            return .allow
        }

        // ---- 组合规则：隐私数据刚被读过，短时间内外发 → 视为组合外泄 ----
        if tier == .network {
            let key = appId ?? "-"
            lock.lock()
            let touch = touches[key]
            lock.unlock()
            if let t = touch {
                let window = SecurityPolicy.comboWindow(for: t.module)
                if window > 0, Date().timeIntervalSince(t.at) <= window {
                    let reason = "刚调用过「\(SecurityPolicy.displayName(for: t.module))」，紧接着又要向外发送数据"
                    TraceRecorder.shared.record(module: module, method: method,
                                                status: "blocked", appId: appId)
                    postEvent(module: module, method: method, appId: appId,
                              appName: appName, reason: reason)
                    return .denyGrantable(module: module, reason: reason)
                }
            }
        }

        // 记录隐私数据类能力的读取时间点
        if tier == .critical {
            let key = appId ?? "-"
            lock.lock()
            touches[key] = Touch(module: module, at: Date())
            // 顺手清理过期项，避免长跑会话里字典无界增长
            if touches.count > 64 {
                let now = Date()
                touches = touches.filter { now.timeIntervalSince($0.value.at) < 120 }
            }
            lock.unlock()
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
        postEvent(module: module, method: method, appId: appId, appName: appName, reason: nil)
        return .denyGrantable(module: module, reason: nil)
    }

    private func postEvent(module: String, method: String, appId: String?, appName: String?,
                           reason: String?) {
        let event = SecurityEvent(module: module, method: method,
                                  appId: appId, appName: appName,
                                  timestamp: Date(), reason: reason)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .securityCapabilityBlocked, object: event)
        }
    }
}
