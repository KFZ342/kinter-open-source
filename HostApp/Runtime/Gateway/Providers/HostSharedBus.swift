import Foundation

/// 跨小程序实时联动总线（LiveSync）——Kinter 独家能力。
///
/// 微信/支付宝小程序均为单实例运行，没有窗口化多开，更不存在"多个小程序实例
/// 同时运行、实时互通数据"的能力。Kinter 的多任务窗口让多个小程序并排运行，
/// 本总线让它们可以实时联动：
///
/// - `broadcast(topic, payload)`：向其它所有窗口广播事件
/// - `setSharedValue(key, value)`：写入共享值，其它窗口实时收到变更通知
/// - `getSharedValue(key)` / `listSharedValues()`：读取共享值
///
/// 每个窗口会话通过 `registerSession(appId:emitter:)` 注册自己的推送通道
/// （Runner 持有），总线把事件路由到除发送方外的所有其它会话。
final class HostSharedBus {
    static let shared = HostSharedBus()
    private let lock = NSLock()

    /// 窗口会话推送通道：appId -> 事件推送闭包（由 Runner 绑定到对应 WebView 的桥接 emit）
    private var sessions: [String: (String, Any) -> Void] = [:]
    /// 共享值存储（跨窗口共享，生命周期与总线一致）
    private var values: [String: Any] = [:]

    private init() {}

    // MARK: - 会话注册

    func registerSession(appId: String, emitter: @escaping (String, Any) -> Void) {
        lock.lock()
        sessions[appId] = emitter
        lock.unlock()
    }

    func unregisterSession(appId: String) {
        lock.lock()
        sessions.removeValue(forKey: appId)
        lock.unlock()
    }

    /// 当前会话数（HUD / 调试用）
    var sessionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return sessions.count
    }

    // MARK: - 广播

    /// 向除发送方外的所有其它窗口广播事件。
    /// 目标 JS 侧收到事件名 `livesync.broadcast.<topic>`，可用 wx.onBroadcast 订阅。
    func broadcast(from appId: String, topic: String, payload: Any) {
        lock.lock()
        let targets = sessions.filter { $0.key != appId }
        lock.unlock()
        let body: [String: Any] = [
            "topic": topic,
            "payload": payload,
            "from": appId
        ]
        for (_, emit) in targets {
            emit("livesync.broadcast.\(topic)", body)
        }
    }

    // MARK: - 共享值

    /// 写入共享值并通知其它窗口（事件名 `livesync.value.<key>`，可用 wx.onSharedValueChange 订阅）。
    @discardableResult
    func setSharedValue(_ key: String, _ value: Any, from appId: String) -> Bool {
        lock.lock()
        let existed = values[key] != nil
        values[key] = value
        let targets = sessions.filter { $0.key != appId }
        lock.unlock()

        let body: [String: Any] = [
            "key": key,
            "value": value,
            "from": appId,
            "existed": existed
        ]
        for (_, emit) in targets {
            emit("livesync.value.\(key)", body)
        }
        return true
    }

    func getSharedValue(_ key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func listSharedValues() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return values
    }

    func removeSharedValue(_ key: String, from appId: String) {
        lock.lock()
        values.removeValue(forKey: key)
        let targets = sessions.filter { $0.key != appId }
        lock.unlock()
        let body: [String: Any] = ["key": key, "from": appId, "removed": true]
        for (_, emit) in targets {
            emit("livesync.value.\(key)", body)
        }
    }
}
