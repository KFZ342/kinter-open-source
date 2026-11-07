import Foundation

/// 安全模式：开启后对敏感能力默认拒绝，所有能力调用记录到 TraceRecorder。
/// 设计原则：默认安全、全程可见、可事后追溯。
final class SecurityMode {
    static let shared = SecurityMode()
    private let defaults = UserDefaults.standard
    private let key = "security.mode.enabled"
    /// 缓存开关状态，避免每次能力调用都读 UserDefaults（网关热路径）。
    private var cachedEnabled: Bool

    private init() {
        cachedEnabled = defaults.bool(forKey: key)
        if cachedEnabled {
            SessionSeed.startNewSession()
            OneShotGrant.shared.reset()
            TraceRecorder.shared.beginSession()
        }
    }

    var isEnabled: Bool {
        get { cachedEnabled }
        set {
            guard newValue != cachedEnabled else { return }
            cachedEnabled = newValue
            defaults.set(newValue, forKey: key)
            // 切模式 = 切会话：清掉上一轮的放行令牌，避免跨会话残留
            OneShotGrant.shared.reset()
            if newValue {
                SessionSeed.startNewSession()
                TraceRecorder.shared.beginSession()
            } else {
                PendingCapabilityStore.shared.drain()
                TraceRecorder.shared.endSession()
            }
            NotificationCenter.default.post(name: .securityModeDidChange, object: newValue)
        }
    }

    /// 敏感能力判定委托给 SecurityPolicy（三级分级，防误判）。
    static func isSensitive(_ module: String) -> Bool {
        SecurityPolicy.isSensitive(module)
    }

    /// 敏感能力的中文名（横幅用）
    static func displayName(for module: String) -> String {
        SecurityPolicy.displayName(for: module)
    }
}
