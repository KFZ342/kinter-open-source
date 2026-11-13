import Foundation
import UIKit

/// Web 访问服务：本机起一个 HTTP 服务，浏览器请求它，它再把请求转成 CapabilityGateway 调用。
///
/// 为什么这样设计：
/// - 能力实现都依赖 UIKit / 系统授权，只能跑在 App 进程里，所以服务必须内置在宿主里；
/// - Web 端拿到的能力边界与小程序一致：manifest 声明 -> 用户禁用 -> 安全模式 -> 系统授权，四道检查全走网关；
/// - 服务只监听局域网，且所有数据接口都要令牌，避免同一 Wi-Fi 下被随意调用。
final class WebAccessService {

    static let shared = WebAccessService()

    /// Web 会话在网关 / 安全事件里显示的身份
    static let webAppId = "kinter.webaccess"
    static let webAppName = "Web 端访问"

    private let settings = WebAccessSettings.shared
    private var server: LocalHTTPServer?
    private var gateway: CapabilityGateway?

    private let eventQueue = DispatchQueue(label: "com.kinter.webaccess.events")
    private var events: [[String: Any]] = []
    private var eventSeq = 0
    private var longPollWaiters: [(since: Int, completion: (HTTPResponse) -> Void)] = []

    /// Web 端最近在干什么（宿主 UI 的横幅用它做实时展示）
    struct WebActivity {
        let label: String
        let appId: String?
        let at: Date
    }

    private(set) var webActivity: WebActivity?
    /// 最近一次带令牌请求的时间，用来判断 Web 端是否还在线
    private(set) var lastClientSeenAt: Date?
    /// Web 端主动注销后置位：横幅显示"已退出"，直到用户在 App 里点 × 关闭
    private(set) var webLoggedOut = false

    /// 服务状态回调（UI 刷新用）
    var onStateChange: ((Bool, UInt16?) -> Void)?
    /// Web 活动回调（主线程）
    var onActivityChange: ((WebActivity?) -> Void)?

    private(set) var runningPort: UInt16?

    private init() {
        // App 进后台即关停本地服务并作废旧令牌，避免后台挂着监听窗口；
        // 回前台后按上次 autoStart 偏好自动恢复。
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    @objc private func handleEnterBackground() {
        if isRunning { stop() }
    }

    @objc private func handleEnterForeground() {
        if settings.autoStart, !isRunning {
            DispatchQueue.global(qos: .utility).async { try? WebAccessService.shared.start() }
        }
    }

    var isRunning: Bool { server?.isRunning ?? false }

    /// 浏览器可访问的地址（拿不到局域网 IP 时返回 nil）
    var baseURL: String? {
        guard let port = runningPort else { return nil }
        return LocalNetworkInfo.baseURL(port: port)
    }

    var accessURL: String? {
        guard let base = baseURL else { return nil }
        return "\(base)/?token=\(settings.token)"
    }

    // MARK: - 生命周期

    /// 启动服务，返回实际监听端口
    @discardableResult
    func start() throws -> UInt16 {
        if isRunning, let p = runningPort { return p }

        // 能力注册是幂等的；防止有人在 registerBuiltins 之前就打开了这里
        CapabilityRegistry.shared.registerBuiltins()
        createSession()

        let srv = LocalHTTPServer { [weak self] request, completion in
            guard let self = self else {
                completion(.failure(503, code: "service_gone", message: "服务已释放"))
                return
            }
            self.handle(request, completion: completion)
        }
        // 端口被别的进程占用时自动向后找，最多试 10 个，避免整个服务起不来
        var boundPort: UInt16?
        var lastError: Error?
        for offset in 0..<10 {
            guard let candidate = UInt16(exactly: Int(settings.port) + offset),
                  WebAccessSettings.portRange.contains(candidate) else { break }
            do {
                boundPort = try srv.start(preferredPort: candidate)
                break
            } catch {
                lastError = error
            }
        }
        guard let port = boundPort else {
            throw lastError ?? LocalHTTPServer.ServerError.startTimeout
        }
        if port != settings.port {
            NSLog("[WebAccess] 端口 %d 不可用，改用 %d", Int(settings.port), Int(port))
            settings.port = port        // 记住实际端口，下次启动不用再试探
        }
        server = srv
        runningPort = port
        settings.isEnabled = true
        settings.autoStart = true
        notifyState(true)
        return port
    }

    func stop() {
        stop(revokeToken: true)
    }

    /// 停止服务。revokeToken=false 用于换端口重启：保留当前令牌，避免当前浏览器被无故踢下线。
    private func stop(revokeToken: Bool) {
        server?.stop()
        server = nil
        runningPort = nil
        gateway = nil
        settings.isEnabled = false
        if revokeToken {
            // 关闭服务时作废旧令牌：旧链接、旧 cookie、旧请求头立刻 401
            settings.rotateToken()
            WebAppSessionPool.shared.invalidateAll()
            webActivity = nil
            lastClientSeenAt = nil
            webLoggedOut = false
        }
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            let waiters = self.longPollWaiters
            self.longPollWaiters.removeAll()
            for w in waiters {
                w.completion(.json(["ok": true, "events": [], "seq": self.eventSeq]))
            }
        }
        notifyState(false)
    }

    /// 把请求翻译成一句"人话"，给横幅用
    private static func summarize(_ request: HTTPRequest) -> (label: String, appId: String?) {
        let path = request.path

        if path == "/api/bridge", let body = request.jsonBody {
            let module = body["module"] as? String ?? "capability"
            let method = body["method"] as? String ?? ""
            let appId = body["appId"] as? String
            return ("正在调用能力 \(module).\(method)", appId)
        }
        if path == "/run" {
            let appId = request.query["appId"] ?? ""
            let name = AppLibrary.shared.app(id: appId)?.name ?? "小程序"
            return ("正在运行「\(name)」", appId.isEmpty ? nil : appId)
        }
        if path.hasPrefix("/apps/") {
            let rest = path.dropFirst("/apps/".count)
            let appId = String(rest.split(separator: "/").first ?? "")
            let name = AppLibrary.shared.app(id: appId)?.name
            return ("正在浏览「\(name ?? appId)」", appId)
        }

        switch (request.method, path) {
        case ("POST", "/api/apps/import"):      return ("正在导入小程序安装包", nil)
        case ("POST", "/api/apps/preview"):     return ("正在检查小程序安装包", nil)
        case ("POST", "/api/apps/update"):      return ("正在修改应用设置", nil)
        case ("POST", "/api/apps/delete"):      return ("正在卸载应用", nil)
        case ("GET", "/api/apps"):              return ("正在查看应用库", nil)
        case ("GET", "/api/meta"):              return ("正在查看 Kinter 信息", nil)
        case ("GET", "/api/settings"):          return ("正在查看偏好设置", nil)
        case ("POST", "/api/settings"):         return ("正在修改偏好设置", nil)
        case ("POST", "/api/token/rotate"):     return ("正在重新生成访问令牌", nil)
        case ("POST", "/api/kick"):             return ("正在结束 Web 控制", nil)
        case ("GET", "/api/audit"):             return ("正在查看审计日志", nil)
        case ("POST", "/api/store/install"):    return ("正在从商店安装应用", nil)
        case ("POST", "/api/store/refresh"):    return ("正在刷新商店", nil)
        case ("POST", "/api/store/source"):     return ("正在添加商店源", nil)
        case ("POST", "/api/store/source/remove"): return ("正在移除商店源", nil)
        case ("GET", "/api/store"):             return ("正在查看商店", nil)
        case ("POST", "/api/invoke"):           return ("正在直接调用能力", nil)
        default:                                return ("正在访问 \(path)", nil)
        }
    }

    /// 用户在宿主里点"踢出"：令牌立刻作废，Web 端所有会话失效
    func kickWebControl() {
        settings.rotateToken()
        WebAppSessionPool.shared.invalidateAll()
        webActivity = nil
        lastClientSeenAt = nil
        webLoggedOut = false
        DispatchQueue.main.async { [weak self] in
            self?.onActivityChange?(nil)
        }
    }

    /// Web 端自己点"退出"：同样换令牌，但横幅要留下一条"已退出"提示
    func logoutWebControl() {
        settings.rotateToken()
        WebAppSessionPool.shared.invalidateAll()
        webActivity = nil
        lastClientSeenAt = nil
        webLoggedOut = true
        DispatchQueue.main.async { [weak self] in
            self?.onActivityChange?(nil)
        }
    }

    /// 用户点了横幅上的 ×，收起"已退出"提示
    func dismissLoggedOutNotice() {
        webLoggedOut = false
        DispatchQueue.main.async { [weak self] in
            self?.onActivityChange?(nil)
        }
    }

    /// 探测从 preferred 开始第一个真正可用的端口（临时监听后立刻释放，不影响正在运行的服务）
    func nextAvailablePort(startingAt preferred: UInt16, attempts: Int = 10) -> UInt16 {
        let probe = LocalHTTPServer { _, completion in completion(.empty(status: 204)) }
        defer { probe.stop() }
        for offset in 0..<attempts {
            guard let candidate = UInt16(exactly: Int(preferred) + offset),
                  WebAccessSettings.portRange.contains(candidate) else { break }
            if let bound = try? probe.start(preferredPort: candidate) { return bound }
        }
        return preferred
    }

    /// 改端口后重启（保留当前令牌）
    @discardableResult
    func restart(withPort port: UInt16) throws -> UInt16 {
        stop(revokeToken: false)
        server = nil
        runningPort = nil
        settings.port = port
        return try start()
    }

    /// 轮换令牌：旧令牌立刻失效
    func rotateToken() {
        settings.rotateToken()
    }

    private func publishActivityIfNeeded() {
        // 占位：目前只在请求入口和踢出时推送，保留给后续状态细化
    }

    private func notifyState(_ running: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onStateChange?(running, self.runningPort)
        }
    }

    // MARK: - 会话

    /// 为 Web 端建立一个独立网关会话，manifest 声明除 L3 外的全部已注册能力。
    private func createSession() {
        let levels = CapabilityRegistry.shared.allCapabilities()
        var decls: [String: MiniAppManifest.CapabilityDecl] = [:]
        for (cap, level) in levels {
            guard level != .l3 else { continue }
            if SecurityPolicy.isHardDenied(cap) { continue }
            decls[cap] = MiniAppManifest.CapabilityDecl(level: level.rawValue,
                                                       reason: "Web 端访问",
                                                       scope: "web")
        }

        let manifest = MiniAppManifest(appId: Self.webAppId,
                                       version: "1.0",
                                       name: Self.webAppName,
                                       minHostVersion: nil,
                                       pages: ["/"],
                                       capabilities: decls,
                                       window: nil,
                                       icon: nil,
                                       price: nil)

        let gw = CapabilityGateway()
        gw.setManifest(manifest)
        // 安全模式下用户可在 App 内一键信任该会话；这里不预置任何放行
        gw.setDisabledCapabilities([])
        gw.bindEmitters { [weak self] event, data in
            self?.appendEvent(event: event, data: data)
        }
        gateway = gw
    }

    // MARK: - 路由

    private func handle(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        // 预检请求不需要令牌，但只放行同源；跨源预检直接拒绝
        if request.method == "OPTIONS" {
            guard WebHTTP.isSameOrigin(request) else {
                completion(WebHTTP.cors(.failure(403, code: "cross_origin", message: "跨源请求被拒绝")))
                return
            }
            var resp = WebHTTP.cors(.empty(status: 204))
            resp.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
            resp.headers["Access-Control-Allow-Headers"] = "Content-Type, X-Kinter-Token, Authorization"
            resp.headers["Access-Control-Max-Age"] = "600"
            completion(resp)
            return
        }

        // 免鉴权：控制台外壳 / 样式脚本 / 探活
        switch (request.method, request.path) {
        case ("GET", "/healthz"):
            completion(WebHTTP.cors(.json(["ok": true])))
            return
        case ("GET", "/"), ("GET", "/index.html"):
            var resp = WebHTTP.cors(HTTPResponse(status: 200,
                                                 headers: ["Content-Type": "text/html; charset=utf-8",
                                                           "Cache-Control": "no-store"],
                                                 body: Data(renderConsolePage().utf8)))
            // 地址里带了有效令牌，就顺手种一个 HttpOnly cookie：
            // 之后同一浏览器打开 /run、/apps 等页面（没法带请求头）也能自动通过鉴权。
            if let t = request.query["token"], WebAccessSettings.matches(t, settings.token) {
                resp.headers["Set-Cookie"] = "kinter_web=\(settings.token); Path=/; HttpOnly; SameSite=Strict; Max-Age=604800"
            }
            completion(resp)
            return
        case ("GET", "/favicon.ico"):
            completion(.empty(status: 404))
            return
        case ("GET", "/manifest.webmanifest"), ("GET", "/sw.js"):
            let name = String(request.path.dropFirst())
            guard let body = Self.bundledText(name: (name as NSString).deletingPathExtension,
                                              ext: (name as NSString).pathExtension) else {
                completion(WebHTTP.cors(.failure(404, code: "not_found", message: "资源缺失：\(name)")))
                return
            }
            let isSW = name.hasSuffix(".js")
            var resp = HTTPResponse(status: 200,
                                    headers: ["Content-Type": isSW
                                                ? "application/javascript; charset=utf-8"
                                                : "application/manifest+json; charset=utf-8",
                                              "Cache-Control": isSW ? "no-cache" : "public, max-age=3600"],
                                    body: Data(body.utf8))
            if isSW { resp.headers["Service-Worker-Allowed"] = "/" }
            completion(WebHTTP.cors(resp))
            return
        case ("GET", "/pwa-192.png"), ("GET", "/pwa-512.png"),
             ("GET", "/pwa-180.png"), ("GET", "/apple-touch-icon.png"):
            let file = request.path == "/apple-touch-icon.png" ? "pwa-180" : String(request.path.dropFirst().dropLast(4))
            guard let data = Self.bundledData(name: file, ext: "png") else {
                completion(WebHTTP.cors(.failure(404, code: "not_found", message: "图标缺失")))
                return
            }
            completion(WebHTTP.cors(HTTPResponse(status: 200,
                                                headers: ["Content-Type": "image/png",
                                                          "Cache-Control": "public, max-age=86400"],
                                                body: data)))
            return
        case ("GET", "/console.css"), ("GET", "/console.js"),
             ("GET", "/web-bridge.js"), ("GET", "/web-bridge-v2.js"):
            var name = String(request.path.dropFirst())
            // v2 是同一个脚本的新 URL：旧 Service Worker 缓存了 /web-bridge.js，
            // 换路径可以确保升级后一定拿到新代码。
            if name == "web-bridge-v2.js" { name = "web-bridge.js" }
            if let body = Self.bundledText(name: (name as NSString).deletingPathExtension,
                                           ext: (name as NSString).pathExtension) {
                let mime = name.hasSuffix(".css") ? "text/css; charset=utf-8"
                                                  : "application/javascript; charset=utf-8"
                completion(WebHTTP.cors(HTTPResponse(status: 200,
                                                     headers: ["Content-Type": mime,
                                                               "Cache-Control": "no-store"],
                                                     body: Data(body.utf8))))
            } else {
                completion(WebHTTP.cors(.failure(404, code: "not_found", message: "资源缺失：\(name)")))
            }
            return
        default:
            break
        }

        // 其余接口一律要令牌
        guard isAuthorized(request) else {
            completion(WebHTTP.cors(.failure(401, code: "unauthorized",
                                             message: "缺少或错误的访问令牌：请在请求头带上 X-Kinter-Token，或用 ?token= 传参")))
            return
        }

        // 跨源校验：带 Origin 头且与 Host 不同源的请求一律拒绝（防 CSRF / 跨站读取）。
        // 无 Origin 头（同源导航、命令行、本地脚本）不拦截，鉴权仍由令牌把关。
        guard WebHTTP.isSameOrigin(request) else {
            completion(WebHTTP.authorized(.failure(403, code: "cross_origin",
                                                  message: "跨源请求被拒绝"), for: request))
            return
        }

        // 令牌是走请求头 / 查询串带过来的（控制台存在 localStorage 里），
        // 顺手换成 cookie，后面 iframe 里的页面请求（带不了请求头）才能过鉴权。
        let needsCookie = !Self.hasValidCookie(request, expected: settings.token)

        // 记录 Web 端正在做什么：轮询不参与展示，但要算"在线"
        lastClientSeenAt = Date()
        if webLoggedOut {
            // 换了新令牌重新连上来，退出提示自动失效
            webLoggedOut = false
        }
        if request.path != "/api/poll" {
            let summary = Self.summarize(request)
            let activity = WebActivity(label: summary.label, appId: summary.appId, at: Date())
            webActivity = activity
            DispatchQueue.main.async { [weak self] in
                self?.onActivityChange?(activity)
            }
        }

        func finish(_ response: HTTPResponse) {
            self.publishActivityIfNeeded()
            var resp = WebHTTP.authorized(response, for: request)
            if needsCookie {
                resp.headers["Set-Cookie"] = "kinter_web=\(settings.token); Path=/; HttpOnly; SameSite=Strict; Max-Age=604800"
            }
            completion(resp)
        }

        switch (request.method, request.path) {
        case ("GET", "/api/meta"):
            finish(WebHTTP.cors(.json(metaPayload())))
            return
        case ("GET", "/api/capabilities"):
            finish(WebHTTP.cors(.json(["ok": true, "capabilities": capabilityPayload()])))
            return
        case ("POST", "/api/invoke"):
            handleInvoke(request, completion: finish)
            return
        case ("GET", "/api/audit"):
            finish(WebHTTP.cors(.json(["ok": true, "lines": auditLines(limit: auditLimit(request))])))
            return
        case ("GET", "/api/poll"):
            handlePoll(request, completion: finish)
            return
        default:
            break
        }

        // App 本体业务：应用库 / 导入 / 运行 / 设置 / 商店
        if WebAppRoutes.shared.route(request, completion: finish) { return }

        finish(WebHTTP.cors(.failure(404, code: "not_found", message: "未知接口：\(request.path)")))
    }

    /// 供 WebAppRoutes 读取打包进来的页面资源
    func bundledConsole(name: String, ext: String) -> String? {
        Self.bundledText(name: name, ext: ext)
    }

    // MARK: - 鉴权

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let expected = settings.token
        // 允许的写法：X-Kinter-Token / Authorization: Bearer / ?token= / HttpOnly cookie
        if let t = request.header("x-kinter-token"),
           WebAccessSettings.matches(t, expected) { return true }
        if let auth = request.header("authorization"),
           auth.lowercased().hasPrefix("bearer ") {
            let t = String(auth.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            if WebAccessSettings.matches(t, expected) { return true }
        }
        if let q = request.query["token"], WebAccessSettings.matches(q, expected) { return true }
        if let cookie = request.header("cookie"),
           let token = Self.cookieValue(named: "kinter_web", in: cookie),
           WebAccessSettings.matches(token, expected) { return true }
        return false
    }

    private static func hasValidCookie(_ request: HTTPRequest, expected: String) -> Bool {
        guard let cookie = request.header("cookie"),
              let token = cookieValue(named: "kinter_web", in: cookie) else { return false }
        return WebAccessSettings.matches(token, expected)
    }

    private static func cookieValue(named name: String, in header: String) -> String? {
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            if key == name, kv.count > 1 { return String(kv[1]) }
        }
        return nil
    }

    private func withCORS(_ response: HTTPResponse, for request: HTTPRequest) -> HTTPResponse {
        WebHTTP.authorized(response, for: request)
    }

    // MARK: - 数据

    private func metaPayload() -> [String: Any] {
        let info = Bundle.main.infoDictionary
        var payload: [String: Any] = [
            "ok": true,
            "app": "Kinter",
            "version": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info?["CFBundleVersion"] as? String ?? "unknown",
            "device": UIDevice.current.model,
            "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "session": Self.webAppId,
            "sessionName": Self.webAppName,
            "securityMode": SecurityMode.shared.isEnabled,
            "port": Int(runningPort ?? 0),
            "baseURL": baseURL ?? ""
        ]
        if let url = accessURL { payload["accessURL"] = url }

        // Kinter 信息面板用的宿主数据
        let apps = AppLibrary.shared.apps
        payload["installedApps"] = apps.count
        payload["categories"] = AppLibrary.shared.categories.count
        payload["capabilityCount"] = CapabilityRegistry.shared.allCapabilities().filter { $0.value != .l3 }.count
        payload["platform"] = "iOS"
        payload["localIP"] = LocalNetworkInfo.primaryIPv4() ?? ""
        if let user = KinterAuthManager.shared.restoreSession() {
            payload["account"] = ["loggedIn": true, "name": user.displayName, "username": user.username] as [String: Any]
        } else {
            payload["account"] = ["loggedIn": false] as [String: Any]
        }
        return payload
    }

    private func capabilityPayload() -> [[String: Any]] {
        let levels = CapabilityRegistry.shared.allCapabilities()
        return levels
            .filter { $0.value != .l3 }
            .sorted { $0.key < $1.key }
            .map { (cap, level) -> [String: Any] in
                let info = PermissionCatalog.all.first(where: { $0.id == cap })
                return [
                    "module": cap,
                    "level": level.rawValue,
                    "name": info?.displayName ?? cap,
                    "detail": info?.detail ?? "",
                    "sensitive": SecurityMode.isSensitive(cap),
                    "hardDenied": SecurityPolicy.isHardDenied(cap)
                ]
            }
    }

    private func auditLimit(_ request: HTTPRequest) -> Int {
        let raw = Int(request.query["limit"] ?? "50") ?? 50
        return min(max(raw, 1), 500)
    }

    private func auditLines(limit: Int) -> [String] {
        let url = AuditLog.logFileURL
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        return Array(lines.suffix(limit)).map(String.init)
    }

    // MARK: - 调用

    private func handleInvoke(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody else {
            completion(self.withCORS(.failure(400, code: "invalid_params",
                                         message: "请求体必须是 JSON，例如 {\"module\":\"deviceInfo\",\"method\":\"getInfo\"}"), for: request))
            return
        }
        // 兼容 module / capability 两种字段名
        guard let module = (body["module"] as? String) ?? (body["capability"] as? String),
              let method = body["method"] as? String else {
            completion(self.withCORS(.failure(400, code: "invalid_params",
                                         message: "缺少 module 或 method 字段"), for: request))
            return
        }
        let params = body["params"] as? [String: Any] ?? [:]

        guard let gw = gateway else {
            completion(self.withCORS(.failure(503, code: "service_gone",
                                         message: "服务会话已释放，请重新开启 Web 访问"), for: request))
            return
        }

        // Provider 大量依赖 UIKit / 系统授权弹窗，必须回主线程调用
        DispatchQueue.main.async {
            gw.invoke(module: module, method: method, params: params) { result in
                switch result {
                case .success(let value):
                    completion(self.withCORS(.json(["ok": true, "data": Self.jsonSafe(value)]), for: request))
                case .failure(let error):
                    completion(self.withCORS(.json([
                        "ok": false,
                        "error": error.asJSON
                    ]), for: request))
                }
            }
        }
    }

    /// 把 Provider 返回值转成 JSON 可序列化结构：
    /// 字典/数组/字符串/数字直接可用；Data 转 base64；其它类型转字符串兜底。
    static func jsonSafe(_ value: Any) -> Any {
        if JSONSerialization.isValidJSONObject(value) { return value }
        switch value {
        case let d as Data:
            return ["__type": "base64", "data": d.base64EncodedString()]
        case let s as String:
            return s
        case let n as NSNumber:
            return n
        case let b as Bool:
            return b
        case let arr as [Any]:
            return arr.map { jsonSafe($0) }
        case let dict as [String: Any]:
            return dict.mapValues { jsonSafe($0) }
        default:
            return String(describing: value)
        }
    }

    // MARK: - 事件（长轮询）

    func appendEvent(event: String, data: Any) {
        appendEvent(appId: Self.webAppId, event: event, data: data)
    }

    func appendEvent(appId: String, event: String, data: Any) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            self.eventSeq += 1
            let payload: [String: Any] = [
                "seq": self.eventSeq,
                "appId": appId,
                "event": event,
                "data": WebAccessService.jsonSafe(data)
            ]
            self.events.append(payload)
            if self.events.count > 200 { self.events.removeFirst(self.events.count - 200) }
            self.flushWaiters()
        }
    }

    /// 给运行中的 Web 小程序挂上事件出口（websocket / 网络变化等推给长轮询）
    func attachEvents(to session: WebAppSession) {
        session.onEvent = { [weak self] event, data in
            self?.appendEvent(appId: session.appId, event: event, data: data)
        }
    }

    /// 取 since 之后的事件（必须在 eventQueue 上调用）；appId 非空时只返回该应用的事件
    private func eventsAfter(_ since: Int, appId: String? = nil) -> [[String: Any]] {
        events.filter {
            let newer = ($0["seq"] as? Int ?? 0) > since
            if let appId = appId { return newer && ($0["appId"] as? String) == appId }
            return newer
        }
    }

    private func flushWaiters() {
        guard !longPollWaiters.isEmpty else { return }
        let ready = longPollWaiters.filter { !eventsAfter($0.since).isEmpty }
        guard !ready.isEmpty else { return }
        longPollWaiters.removeAll { !eventsAfter($0.since).isEmpty }
        for waiter in ready {
            waiter.completion(.json([
                "ok": true,
                "seq": eventSeq,
                "events": eventsAfter(waiter.since)
            ]))
        }
    }

    private func handlePoll(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        let since = Int(request.query["since"] ?? "0") ?? 0
        let waitSeconds = min(max(Int(request.query["wait"] ?? "20") ?? 20, 0), 25)
        let filterApp = request.query["appId"]

        eventQueue.async { [weak self] in
            guard let self = self else {
                completion(.json(["ok": true, "events": [], "seq": 0]))
                return
            }
            let pending = self.eventsAfter(since, appId: filterApp)
            if !pending.isEmpty || waitSeconds == 0 {
                completion(.json(["ok": true, "seq": self.eventSeq, "events": pending]))
                return
            }
            // 挂起等待新事件，超时返回空
            let waiterSince = since
            self.longPollWaiters.append((since: waiterSince, completion: completion))
            self.eventQueue.asyncAfter(deadline: .now() + .seconds(waitSeconds)) { [weak self] in
                guard let self = self else { return }
                guard let idx = self.longPollWaiters.firstIndex(where: { $0.since == waiterSince }) else {
                    return
                }
                self.longPollWaiters.remove(at: idx)
                completion(.json(["ok": true, "seq": self.eventSeq,
                                  "events": self.eventsAfter(waiterSince, appId: filterApp)]))
            }
        }
    }

    // MARK: - 页面

    private func renderConsolePage() -> String {
        return Self.bundledText(name: "kinter-console", ext: "html")
            ?? "<!doctype html><meta charset=\"utf-8\"><title>Kinter Web</title><p>控制台页面缺失，请重新构建 App。"
    }

    /// 资源可能被平铺到 bundle 根目录，也可能保留 web/ 子目录，两处都找一次。
    private static func bundledData(name: String, ext: String) -> Data? {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "web"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/web"),
            Bundle.main.url(forResource: name, withExtension: ext)
        ].compactMap { $0 }
        for url in candidates {
            if let d = try? Data(contentsOf: url) { return d }
        }
        return nil
    }

    private static func bundledText(name: String, ext: String) -> String? {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "web"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/web"),
            Bundle.main.url(forResource: name, withExtension: ext)
        ].compactMap { $0 }
        for url in candidates {
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return nil
    }
}
