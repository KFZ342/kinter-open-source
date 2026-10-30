import UIKit
import WebKit

/// WKWebView 消息桥。JS postMessage -> 这里 -> Gateway -> 回传 JS。
final class BridgeMessageHandler: NSObject, WKScriptMessageHandler {
    static let handlerName = "bridge"

    private weak var webView: WKWebView?
    /// 所属小程序会话的网关实例
    private let gateway: CapabilityGateway
    /// DEBUG 日志节流：同一 module.method 高频调用（轮询类）只周期打印，避免刷屏拖慢桥接
    private var debugLogCount: [String: Int] = [:]

    init(webView: WKWebView, gateway: CapabilityGateway) {
        self.webView = webView
        self.gateway = gateway
        super.init()
    }

    /// 性能统计（DevHUD 读取）
    private(set) var callCount = 0
    private(set) var errorCount = 0
    /// 最近一次网关调用的往返耗时（秒）
    private(set) var lastCallDuration: TimeInterval = 0

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName,
              let body = message.body as? [String: Any],
              let module = body["module"] as? String,
              let method = body["method"] as? String,
              let callbackId = body["callbackId"] as? String else {
            return
        }
        let params = body["params"] as? [String: Any] ?? [:]
        callCount += 1
#if DEBUG
        // 只记录模块与方法，不打印 params（可能含 token/密码等敏感数据，且高频调用会刷日志）。
        // 节流：同一 module.method 每 100 次打印一次（首条必打，便于定位调用来源）。
        let key = "\(module).\(method)"
        let count = (debugLogCount[key] ?? 0) + 1
        debugLogCount[key] = count
        if count == 1 || count % 100 == 0 {
            NSLog("[Bridge] %@.%@ ×%d", module, method, count)
        }
#endif

        // 路由模块由原生直接处理，不经过能力网关
        if module == "router" {
            NSLog("[Bridge] routing to handleRouter")
            handleRouter(method: method, params: params, callbackId: callbackId)
            return
        }

        // 应用级全局存储，不走能力网关
        if module == "store" {
            handleStore(method: method, params: params, callbackId: callbackId)
            return
        }

        // 账号信息（只读）
        if module == "auth" {
            handleAuth(method: method, params: params, callbackId: callbackId)
            return
        }

        // 应用间调用
        if module == "app" {
            handleAppInterop(method: method, params: params, callbackId: callbackId)
            return
        }

        // 宿主自绘弹窗
        if module == "popup" {
            handlePopup(method: method, params: params, callbackId: callbackId)
            return
        }

        // iOS 原生权限深度集成
        if module == "permission" {
            handlePermission(method: method, params: params, callbackId: callbackId)
            return
        }

        gateway.invoke(module: module,
                                        method: method,
                                        params: params) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure = result { self.errorCount += 1 }
                self.sendBack(callbackId: callbackId, result: result)
            }
        }
    }

    private func sendBack(callbackId: String, result: Result<Any, GatewayError>) {
        var payload: [String: Any] = ["callbackId": callbackId]
        switch result {
        case .success(let data):
            payload["ok"] = true
            payload["data"] = data
        case .failure(let err):
            payload["ok"] = false
            payload["error"] = err.asJSON
        }
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let str = String(data: json, encoding: .utf8) else { return }
        let js = "window.__wxBridgeCallback && window.__wxBridgeCallback(\(str));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - 页面路由

    /// 由 Runner 注入
    var pageRouter: PageRouter?

    private func handleRouter(method: String, params: [String: Any], callbackId: String) {
        guard let router = pageRouter else {
            sendRouterResult(callbackId: callbackId,
                             ok: false,
                             error: ["code": "router_unavailable", "message": "页面路由未初始化"])
            return
        }
        do {
            switch method {
            case "navigateTo":
                let url = params["url"] as? String ?? ""
                try router.navigateTo(url)
                sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])
            case "redirectTo":
                let url = params["url"] as? String ?? ""
                try router.redirectTo(url)
                sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])
            case "reLaunch":
                let url = params["url"] as? String ?? ""
                try router.reLaunch(url)
                sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])
            case "navigateBack":
                let delta = params["delta"] as? Int ?? 1
                try router.navigateBack(delta: delta)
                sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])
            case "getStack":
                sendRouterResult(callbackId: callbackId, ok: true, data: ["stack": router.stack])
            default:
                sendRouterResult(callbackId: callbackId,
                                 ok: false,
                                 error: ["code": "method_not_found", "message": "router.\(method)"])
            }
        } catch {
            sendRouterResult(callbackId: callbackId,
                             ok: false,
                             error: ["code": "router_error", "message": error.localizedDescription])
        }
    }

    // MARK: - 全局存储

    /// 由 Runner 注入
    var appStore: AppStore?

    // MARK: - 账号信息

    private func handleAuth(method: String, params: [String: Any], callbackId: String) {
        switch method {
        case "getUserInfo":
            if let user = KinterAuthManager.shared.restoreSession() {
                sendRouterResult(callbackId: callbackId, ok: true, data: [
                    "loggedIn": true,
                    "user": [
                        "id": user.id,
                        "username": user.username,
                        "name": user.displayName
                    ]
                ])
            } else {
                sendRouterResult(callbackId: callbackId, ok: true, data: ["loggedIn": false])
            }

        case "requestLogin":
            DispatchQueue.main.async {
                if let user = KinterAuthManager.shared.restoreSession() {
                    self.sendRouterResult(callbackId: callbackId, ok: true, data: [
                        "loggedIn": true,
                        "user": [
                            "id": user.id,
                            "username": user.username,
                            "name": user.displayName
                        ]
                    ])
                    return
                }
                guard let top = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                    .first else {
                    self.sendRouterResult(callbackId: callbackId, ok: false,
                                         error: ["code": "unsupported", "message": "无法呈现登录页"])
                    return
                }
                let accountVC = AccountViewController()
                let nav = UINavigationController(rootViewController: accountVC)
                nav.modalPresentationStyle = .formSheet
                top.presentSafely(nav, animated: true)
                self.sendRouterResult(callbackId: callbackId, ok: true, data: ["opened": true])
            }

        default:
            sendRouterResult(callbackId: callbackId, ok: false,
                             error: ["code": "method_not_found", "message": "auth.\(method)"])
        }
    }

    // MARK: - 应用间调用

    /// 由 Runner 注入：发起应用跳转。
    /// 参数 (targetAppId, params, completion(success, error))
    var onOpenApp: ((String, [String: Any], @escaping (Bool, String?) -> Void) -> Void)?

    /// 记录本应用接收到的启动参数（供 JS 查询）
    

    private func handleAppInterop(method: String, params: [String: Any], callbackId: String) {
        switch method {
        case "open":
            guard let target = params["appId"] as? String, !target.isEmpty else {
                sendRouterResult(callbackId: callbackId, ok: false,
                                 error: ["code": "invalid_params", "message": "appId 必填"])
                return
            }
            let extra = params["params"] as? [String: Any] ?? [:]
            guard let opener = onOpenApp else {
                sendRouterResult(callbackId: callbackId, ok: false,
                                 error: ["code": "unsupported", "message": "当前环境不支持应用间调用"])
                return
            }
            opener(target, extra) { success, err in
                DispatchQueue.main.async {
                    if success {
                        self.sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])
                    } else {
                        self.sendRouterResult(callbackId: callbackId, ok: false,
                                             error: ["code": "open_failed", "message": err ?? "无法打开"])
                    }
                }
            }

        case "getLaunchParams":
            let p = gateway.launchParams ?? [:]
            // 取完即清，避免下次启动时误用
            gateway.launchParams = nil
            sendRouterResult(callbackId: callbackId, ok: true, data: ["params": p])

        case "canOpen":
            guard let target = params["appId"] as? String else {
                sendRouterResult(callbackId: callbackId, ok: false,
                                 error: ["code": "invalid_params", "message": "appId 必填"])
                return
            }
            let exists = AppLibrary.shared.isInstalled(target)
            sendRouterResult(callbackId: callbackId, ok: true, data: ["canOpen": exists])

        default:
            sendRouterResult(callbackId: callbackId, ok: false,
                             error: ["code": "method_not_found", "message": "app.\(method)"])
        }
    }

    // MARK: - 自绘弹窗

    private func handlePopup(method: String, params: [String: Any], callbackId: String) {
        switch method {
        case "toast":
            let text = params["text"] as? String ?? ""
            let duration = params["duration"] as? TimeInterval ?? 1.8
            HostPopup.toast(text, duration: duration)
            sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])

        case "modal":
            let title = params["title"] as? String ?? ""
            let content = params["content"] as? String ?? ""
            let confirm = params["confirmText"] as? String ?? "确定"
            let cancel = params["cancelText"] as? String
            HostPopup.modal(title: title, content: content,
                            confirmText: confirm, cancelText: cancel) { confirmed in
                self.sendRouterResult(callbackId: callbackId, ok: true,
                                      data: ["confirmed": confirmed])
            }

        case "actionSheet":
            let items = params["items"] as? [String] ?? []
            let title = params["title"] as? String
            let cancel = params["cancelText"] as? String ?? "取消"
            HostPopup.actionSheet(items: items, title: title, cancelText: cancel) { index in
                if let idx = index {
                    self.sendRouterResult(callbackId: callbackId, ok: true,
                                          data: ["index": idx, "cancelled": false])
                } else {
                    self.sendRouterResult(callbackId: callbackId, ok: true,
                                          data: ["cancelled": true])
                }
            }

        case "dismissAll":
            HostPopup.dismissAll()
            sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])

        default:
            sendRouterResult(callbackId: callbackId, ok: false,
                             error: ["code": "method_not_found", "message": "popup.\(method)"])
        }
    }

    // MARK: - iOS 原生权限深度集成

    /// 权限模块：查询 / 申请 / 全部状态 / 打开系统设置
    private func handlePermission(method: String, params: [String: Any], callbackId: String) {
        switch method {
        case "getStatus":
            let permission = params["permission"] as? String ?? ""
            guard PermissionManager.supportedIDs.contains(permission) else {
                sendRouterResult(callbackId: callbackId, ok: true,
                                 data: ["permission": permission, "status": "unsupported"])
                return
            }
            PermissionManager.status(for: permission) { [weak self] status in
                self?.sendRouterResult(callbackId: callbackId, ok: true,
                                       data: ["permission": permission, "status": status])
            }

        case "getSetting":
            PermissionManager.allStatuses { [weak self] statuses in
                self?.sendRouterResult(callbackId: callbackId, ok: true, data: statuses)
            }

        case "request":
            let permission = params["permission"] as? String ?? ""
            guard PermissionManager.supportedIDs.contains(permission) else {
                sendRouterResult(callbackId: callbackId, ok: true,
                                 data: ["permission": permission, "status": "unsupported"])
                return
            }
            PermissionManager.request(permission) { [weak self] status in
                self?.sendRouterResult(callbackId: callbackId, ok: true,
                                       data: ["permission": permission, "status": status])
            }

        case "openSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])

        default:
            sendRouterResult(callbackId: callbackId, ok: false,
                             error: ["code": "method_not_found", "message": "permission.\(method)"])
        }
    }

    private func handleStore(method: String, params: [String: Any], callbackId: String) {
        guard let store = appStore else {
            sendRouterResult(callbackId: callbackId, ok: false,
                             error: ["code": "store_unavailable", "message": "存储未初始化"])
            return
        }

        switch method {
        case "set":
            guard let key = params["key"] as? String, !key.isEmpty else {
                sendRouterResult(callbackId: callbackId, ok: false,
                                 error: ["code": "invalid_params", "message": "key 不能为空"])
                return
            }
            store.set(key, value: params["data"])
            sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])

        case "get":
            guard let key = params["key"] as? String else {
                sendRouterResult(callbackId: callbackId, ok: false,
                                 error: ["code": "invalid_params", "message": "key 不能为空"])
                return
            }
            let value = store.get(key)
            sendRouterResult(callbackId: callbackId, ok: true, data: ["data": value ?? NSNull()])

        case "remove":
            guard let key = params["key"] as? String else {
                sendRouterResult(callbackId: callbackId, ok: false,
                                 error: ["code": "invalid_params", "message": "key 不能为空"])
                return
            }
            store.set(key, value: nil)
            sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])

        case "clear":
            store.clear()
            sendRouterResult(callbackId: callbackId, ok: true, data: ["ok": true])

        case "all":
            sendRouterResult(callbackId: callbackId, ok: true, data: ["data": store.all()])

        default:
            sendRouterResult(callbackId: callbackId, ok: false,
                             error: ["code": "method_not_found", "message": "store.\(method)"])
        }
    }

    // MARK: - 主动推送

    /// 事件批量推送缓冲。同一轮 RunLoop 内的多次 emit 合并为一次 evaluateJavaScript，
    /// 高频事件（websocket.message / network.change / 运动监听）从 N 次注入降为 1 次。
    private var pendingEvents: [[String: Any]] = []
    private var eventFlushScheduled = false

    /// 原生向 JS 主动推送事件。JS 侧通过 wx.on(event, handler) 监听。
    func emit(event: String, data: Any) {
        let item: [String: Any] = ["event": event, "data": data]
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pendingEvents.append(item)
            if !self.eventFlushScheduled {
                self.eventFlushScheduled = true
                DispatchQueue.main.async { [weak self] in self?.flushEvents() }
            }
        }
    }

    private func flushEvents() {
        eventFlushScheduled = false
        guard !pendingEvents.isEmpty else { return }
        let batch = pendingEvents
        pendingEvents.removeAll()
        guard let json = try? JSONSerialization.data(withJSONObject: batch, options: []),
              let str = String(data: json, encoding: .utf8) else { return }
        let js = "window.__wxEmitBatch && window.__wxEmitBatch(\(str));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func sendRouterResult(callbackId: String, ok: Bool, data: [String: Any]? = nil, error: [String: Any]? = nil) {
        var payload: [String: Any] = ["callbackId": callbackId, "ok": ok]
        if let data = data { payload["data"] = data }
        if let error = error { payload["error"] = error }
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let str = String(data: json, encoding: .utf8) else { return }
        let js = "window.__wxBridgeCallback && window.__wxBridgeCallback(\(str));"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
