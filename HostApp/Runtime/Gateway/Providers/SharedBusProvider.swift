import Foundation

/// 跨窗口实时联动总线 Provider（sharedbus，L0）——Kinter 独家。
///
/// 多任务窗口下多个小程序实例同时运行，通过本模块实时互通：
/// - `broadcast`            向其它所有窗口广播事件（目标用 wx.onBroadcast 订阅）
/// - `setSharedValue`       写入共享值，其它窗口实时收到变更（wx.onSharedValueChange）
/// - `getSharedValue`       读取共享值
/// - `listSharedValues`     列出全部共享值
/// - `removeSharedValue`    删除共享值并通知
///
/// 事件由 HostSharedBus 路由到其它会话的 WebView（宿主→JS 推送，复用 wx.on 通道）。
final class SharedBusProvider: CapabilityProvider, AppContextInjectable {
    static var capability: String { "sharedbus" }
    static var level: CapabilityLevel { .l0 }

    var appId: String?
    private let bus = HostSharedBus.shared

    init() {}

    func invoke(method: String,
                params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let appId = appId else {
            completion(.failure(.providerError("缺少调用方标识（appId 未注入）")))
            return
        }

        switch method {
        case "broadcast":
            guard let topic = params["topic"] as? String, !topic.isEmpty else {
                completion(.failure(.invalidParams("topic 不能为空")))
                return
            }
            bus.broadcast(from: appId, topic: topic, payload: params["payload"] ?? NSNull())
            completion(.success(["ok": true, "topic": topic, "receivers": bus.sessionCount - 1]))

        case "setSharedValue":
            guard let key = params["key"] as? String, !key.isEmpty else {
                completion(.failure(.invalidParams("key 不能为空")))
                return
            }
            let value = params["value"] ?? NSNull()
            bus.setSharedValue(key, value, from: appId)
            completion(.success(["ok": true, "key": key]))

        case "getSharedValue":
            guard let key = params["key"] as? String, !key.isEmpty else {
                completion(.failure(.invalidParams("key 不能为空")))
                return
            }
            let v = bus.getSharedValue(key)
            completion(.success(["key": key, "value": v ?? NSNull(), "exists": v != nil]))

        case "listSharedValues":
            let all = bus.listSharedValues()
            completion(.success(["count": all.count, "values": all]))

        case "removeSharedValue":
            guard let key = params["key"] as? String, !key.isEmpty else {
                completion(.failure(.invalidParams("key 不能为空")))
                return
            }
            bus.removeSharedValue(key, from: appId)
            completion(.success(["ok": true, "key": key]))

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
