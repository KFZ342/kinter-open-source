import Foundation

/// 一次被拦截或放行的敏感能力调用事件（供横幅/报告展示）。
struct SecurityEvent {
    let module: String
    let method: String
    /// 归属小程序；直通模块（auth/app/permission）拿不到 appId 时为 nil
    let appId: String?
    let appName: String?
    let timestamp: Date
    /// 被拦时的中文描述，如 "相机"
    var displayName: String { SecurityMode.displayName(for: module) }

    /// 授权令牌键。
    /// - 敏感能力：按能力粒度（camera），一次授权对该能力的任意方法生效，避免连点。
    /// - 直通模块（无分级）：按「模块.方法」粒度（auth.getUserInfo），避免一次授权
    ///   把整个模块放开。
    var grantKey: String {
        SecurityPolicy.tier(of: module) == nil && !method.isEmpty
            ? "\(module).\(method)"
            : module
    }
}

/// 一次性放行令牌。
/// 用户点「允许本次」后写入 (sessionId, appId, 能力) 令牌；
/// 网关/桥接每次拦截敏感能力前先查令牌，命中即消费掉（只生效一次）。
final class OneShotGrant {
    static let shared = OneShotGrant()
    private var grants: Set<String> = []
    private let lock = NSLock()

    private init() {}

    private func key(_ sessionId: String, _ appId: String?, _ module: String) -> String {
        "\(sessionId)::\(appId ?? "-")::\(module)"
    }

    /// 发放一次性令牌。appId 参与键，避免同一会话内 A 小程序拿到的授权被 B 消费。
    func grant(module: String, appId: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        grants.insert(key(SessionSeed.sessionId, appId, module))
    }

    /// 消费令牌：有则删除并返回 true（只能用一次）。
    func consume(module: String, appId: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return grants.remove(key(SessionSeed.sessionId, appId, module)) != nil
    }

    /// 会话切换时清空，避免跨会话残留。
    func reset() {
        lock.lock(); defer { lock.unlock() }
        grants.removeAll()
    }
}

// MARK: - 通知常量

/// 安全模式相关通知，全项目统一从这里引用，避免裸字符串拼错。
extension Notification.Name {
    /// 安全模式开关变化，object = Bool
    static let securityModeDidChange = Notification.Name("kinter.security.modeDidChange")
    /// 敏感能力被拦截，object = SecurityEvent
    static let securityCapabilityBlocked = Notification.Name("kinter.security.blocked")
    /// 敏感能力被放行（一次性授权），object = SecurityEvent
    static let securityCapabilityGranted = Notification.Name("kinter.security.granted")
}
