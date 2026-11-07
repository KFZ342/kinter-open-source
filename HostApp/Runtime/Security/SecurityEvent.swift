import Foundation

/// 一次被拦截或放行的敏感能力调用事件（供横幅/报告展示）。
struct SecurityEvent {
    let module: String
    let method: String
    /// 归属小程序；直通模块（auth/app/permission）拿不到 appId 时为 nil
    let appId: String?
    let appName: String?
    let timestamp: Date
    /// 被拦的具体原因（组合规则等），nil 表示普通拦截
    var reason: String? = nil
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

// MARK: - 挂起队列

/// 被安全模式拦下后「挂起」的能力调用。
///
/// 以前的做法是：网关立刻回 permission_denied，用户点「允许本次」后要自己回小程序再点一遍。
/// 现在把这次调用留在这里等 45 秒，用户一按按钮就原样重放——按钮按完，事情就做完了。
final class PendingCapabilityStore {
    static let shared = PendingCapabilityStore()
    private init() {}

    private struct Entry {
        let id = UUID()
        let appId: String?
        let module: String
        let method: String
        let run: () -> Void
        let fail: () -> Void
    }

    private var entries: [Entry] = []
    private let lock = NSLock()
    /// 等用户点击的上限；超过就明确失败，不让 JS 一直挂着
    private let ttl: TimeInterval = 45
    /// 挂起上限：再多就不是"用户在操作"，而是有人在刷接口
    private let capacity = 32

    func park(appId: String?, module: String, method: String,
              run: @escaping () -> Void, fail: @escaping () -> Void) {
        let entry = Entry(appId: appId, module: module, method: method, run: run, fail: fail)
        lock.lock()
        // 同一能力的同一方法已在排队：合并，避免一次授权连开两个相机
        if entries.contains(where: { $0.appId == appId && $0.module == module && $0.method == method }) {
            lock.unlock()
            return
        }
        if entries.count >= capacity {
            lock.unlock()
            fail()
            return
        }
        entries.append(entry)
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + ttl) { [weak self] in
            self?.expire(entry.id)
        }
    }

    /// 用户放行后重放本能力的全部挂起请求。
    func resume(appId: String?, module: String) {
        lock.lock()
        let matched = entries.filter { $0.appId == appId && $0.module == module }
        entries.removeAll { $0.appId == appId && $0.module == module }
        lock.unlock()
        for e in matched { e.run() }
    }

    /// 关闭安全模式 / 切会话时丢弃全部挂起请求，并给调用方一个明确失败。
    func drain() {
        lock.lock()
        let all = entries
        entries.removeAll()
        lock.unlock()
        all.forEach { $0.fail() }
    }

    private func expire(_ id: UUID) {
        lock.lock()
        guard let i = entries.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
        let e = entries.remove(at: i)
        lock.unlock()
        e.fail()
    }
}
