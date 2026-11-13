import Foundation
import UIKit

/// Web 端与「App 本体」对应的接口：应用库、导入、运行、设置、商店。
/// 能力调用（/api/invoke）在 WebAccessService 里，这里只负责宿主业务。
final class WebAppRoutes {

    static let shared = WebAppRoutes()
    private init() {}

    private let settings = WebAccessSettings.shared

    /// 返回 true 表示这条请求已被本类处理。
    func route(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) -> Bool {
        let path = request.path

        // 小程序资源与页面
        if path.hasPrefix("/apps/") {
            serveAppPath(request, completion: completion)
            return true
        }
        if path == "/run" {
            completion(WebHTTP.cors(.html(WebAccessService.shared.bundledConsole(name: "runner", ext: "html")
                                          ?? "<!doctype html><meta charset='utf-8'><p>运行器页面缺失")))
            return true
        }
        if path.hasPrefix("/sdk/") {
            let name = String(path.dropFirst("/sdk/".count))
            if let js = WebAppAssets.sdkScript(named: (name as NSString).deletingPathExtension) {
                completion(WebHTTP.cors(HTTPResponse(status: 200,
                                                     headers: ["Content-Type": "application/javascript; charset=utf-8",
                                                               "Cache-Control": "public, max-age=600"],
                                                     body: Data(js.utf8))))
            } else {
                completion(WebHTTP.cors(.failure(404, code: "not_found", message: "SDK 缺失：\(name)")))
            }
            return true
        }

        switch (request.method, path) {
        case ("GET", "/api/apps"):
            completion(WebHTTP.cors(.json(["ok": true, "apps": appsPayload()])))
            return true

        case ("GET", _) where path.hasSuffix("/icon") && path.hasPrefix("/api/apps/"):
            let appId = path.dropFirst("/api/apps/".count).replacingOccurrences(of: "/icon", with: "")
            if let app = AppLibrary.shared.app(id: String(appId)) {
                completion(WebHTTP.cors(WebAppAssets.iconResponse(app: app)))
            } else {
                completion(WebHTTP.cors(.failure(404, code: "not_found", message: "应用未安装")))
            }
            return true

        case ("POST", "/api/apps/preview"):
            handlePreview(request, completion: completion)
            return true

        case ("POST", "/api/apps/import"):
            handleImport(request, completion: completion)
            return true

        case ("POST", "/api/logout"):
            WebAccessService.shared.logoutWebControl()
            var resp = HTTPResponse.json(["ok": true, "loggedOut": true])
            // 这个浏览器的 HttpOnly cookie 也一起失效，避免它继续带着旧令牌请求
            resp.headers["Set-Cookie"] = "kinter_web=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0"
            completion(WebHTTP.cors(resp))
            return true

        case ("POST", "/api/kick"):
            WebAccessService.shared.kickWebControl()
            completion(WebHTTP.cors(.json(["ok": true, "kicked": true])))
            return true

        case ("POST", "/api/token/rotate"):
            WebAccessService.shared.rotateToken()
            let payload = settingsPayload()
            var resp = HTTPResponse.json(["ok": true, "token": settings.token,
                                          "accessURL": WebAccessService.shared.accessURL ?? "",
                                          "settings": payload])
            // 旧 cookie 立刻作废，改种新令牌，否则这个浏览器下一次请求就会 401
            resp.headers["Set-Cookie"] = "kinter_web=\(settings.token); Path=/; HttpOnly; SameSite=Strict; Max-Age=604800"
            completion(WebHTTP.cors(resp))
            return true

        case ("POST", "/api/apps/update"):
            handleUpdate(request, completion: completion)
            return true

        case ("POST", "/api/apps/delete"):
            handleDelete(request, completion: completion)
            return true

        case ("POST", "/api/bridge"):
            handleBridge(request, completion: completion)
            return true

        case ("GET", "/api/settings"):
            completion(WebHTTP.cors(.json(["ok": true, "settings": settingsPayload()])))
            return true

        case ("POST", "/api/settings"):
            handleSettingsUpdate(request, completion: completion)
            return true

        case ("GET", "/api/store"):
            completion(WebHTTP.cors(.json(["ok": true, "store": storePayload()])))
            return true

        case ("POST", "/api/store/source"):
            handleStoreAddSource(request, completion: completion)
            return true

        case ("POST", "/api/store/source/remove"):
            handleStoreRemoveSource(request, completion: completion)
            return true

        case ("POST", "/api/store/refresh"):
            handleStoreRefresh(request, completion: completion)
            return true

        case ("POST", "/api/store/install"):
            handleStoreInstall(request, completion: completion)
            return true

        default:
            return false
        }
    }

    // MARK: - 应用库

    private func appsPayload() -> [[String: Any]] {
        AppLibrary.shared.apps.map { app in
            var caps: [[String: Any]] = []
            var entry = "index"
            if let data = try? Data(contentsOf: app.manifestURL),
               let m = try? ManifestParser.parse(data: data) {
                for (cap, decl) in m.capabilities ?? [:] {
                    let info = PermissionCatalog.all.first(where: { $0.id == cap })
                    caps.append([
                        "module": cap,
                        "level": decl.level,
                        "name": info?.displayName ?? cap,
                        "enabled": !app.disabledCapabilities.contains(cap)
                    ])
                }
                if let first = m.pages.first, !first.isEmpty { entry = first }
            }
            return [
                "appId": app.appId,
                "name": app.name,
                "version": app.version,
                "category": app.category,
                "entry": entry,
                "installedAt": ISO8601DateFormatter().string(from: app.installedAt),
                "iconURL": "/api/apps/\(app.appId)/icon?v=\(Int(app.installedAt.timeIntervalSince1970))",
                "runURL": "/run?appId=\(app.appId)",
                "isAIGenerated": app.isAIGenerated,
                "price": app.price ?? 0,
                "paid": app.paid,
                "disabledCapabilities": Array(app.disabledCapabilities),
                "capabilities": caps
            ]
        }
    }

    // MARK: - 页面与资源

    private func serveAppPath(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        let trimmed = String(request.path.dropFirst("/apps/".count))
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else {
            completion(WebHTTP.cors(.failure(404, code: "not_found", message: "缺少 appId")))
            return
        }
        let appId = String(first)
        guard let app = AppLibrary.shared.app(id: appId) else {
            completion(WebHTTP.cors(.failure(404, code: "app_not_installed", message: "应用未安装：\(appId)")))
            return
        }

        let rest = parts.count > 1 ? String(parts[1]) : ""
        // 页面请求时先把会话建好，保证启动参数、事件推送都就绪
        if let session = WebAppSessionPool.shared.sessionOrCreate(for: appId) {
            WebAccessService.shared.attachEvents(to: session)
        }
        // 带后缀或明确路径 → 按资源处理；裸路径（如 index / pages/detail/detail）→ 按页面处理
        if rest.isEmpty || !rest.contains(".") {
            do {
                let html = try WebAppAssets.renderDocument(app: app, path: rest)
                completion(withCookie(.html(html)))
            } catch {
                completion(withCookie(.failure(404, code: "page_not_found", message: error.localizedDescription)))
            }
            return
        }
        if rest.hasSuffix(".html") || rest.hasSuffix(".ktml") {
            do {
                let html = try WebAppAssets.renderDocument(app: app, path: rest)
                completion(withCookie(.html(html)))
            } catch {
                completion(withCookie(.failure(404, code: "page_not_found", message: error.localizedDescription)))
            }
            return
        }
        completion(WebHTTP.cors(WebAppAssets.assetResponse(app: app, relativePath: rest)))
    }

    /// 页面响应带上 HttpOnly 会话 cookie：
    /// 页面里的脚本不需要（也不应该）拿到令牌，就能让同源的 /api/bridge 通过鉴权。
    private func withCookie(_ response: HTTPResponse) -> HTTPResponse {
        var r = WebHTTP.cors(response)
        r.headers["Set-Cookie"] = "kinter_web=\(settings.token); Path=/; HttpOnly; SameSite=Strict; Max-Age=604800"
        return r
    }

    // MARK: - 导入 / 预览

    private func handlePreview(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let data = request.body.isEmpty ? nil : request.body else {
            completion(WebHTTP.cors(.failure(400, code: "empty_body", message: "请求体为空，请上传 ZIP 安装包")))
            return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinter-preview-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try data.write(to: tmp)
            let preview = try PackageInspector.inspect(zipURL: tmp)
            let m = preview.manifest
            var payload: [String: Any] = [
                "ok": true,
                "appId": m.appId,
                "name": m.name,
                "version": m.version,
                "price": m.price ?? 0,
                "minHostVersion": m.minHostVersion ?? "",
                "pages": m.pages,
                "sensitive": preview.sensitiveCapabilities,
                "standard": preview.standardCapabilities,
                "normal": preview.normalCapabilities,
                "unknown": preview.unknownCapabilities,
                "bytes": data.count,
                "installed": AppLibrary.shared.isInstalled(m.appId)
            ]
            if let icon = m.icon {
                payload["icon"] = icon
            }
            completion(WebHTTP.cors(.json(payload)))
        } catch {
            completion(WebHTTP.cors(.failure(400, code: "invalid_package", message: error.localizedDescription)))
        }
    }

    private func handleImport(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard !request.body.isEmpty else {
            completion(WebHTTP.cors(.failure(400, code: "empty_body", message: "请求体为空，请上传 ZIP 安装包")))
            return
        }
        let overwrite = (request.query["overwrite"] ?? "1") != "0"
        let category = request.query["category"]?.removingPercentEncoding ?? "未分类"

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinter-import-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let work = DispatchWorkItem {
            do {
                try request.body.write(to: tmp)
                let result = try PackageInstaller.shared.install(zipURL: tmp,
                                                                 overwrite: overwrite,
                                                                 category: category)
                WebAppSessionPool.shared.invalidate(result.app.appId)
                NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
                WebAccessService.shared.appendEvent(appId: "kinter.webaccess", event: "library.changed",
                                                    data: ["appId": result.app.appId])
                let payload: [String: Any] = [
                    "ok": true,
                    "appId": result.app.appId,
                    "name": result.app.name,
                    "version": result.app.version,
                    "warnings": result.warnings,
                    "runURL": "/run?appId=\(result.app.appId)"
                ]
                completion(WebHTTP.cors(.json(payload)))
            } catch {
                completion(WebHTTP.cors(.failure(400, code: "install_failed",
                                                 message: error.localizedDescription)))
            }
        }
        // 解压 + 落盘是 IO 密集，别堵住网络队列
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func handleUpdate(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody, let appId = body["appId"] as? String else {
            completion(WebHTTP.cors(.failure(400, code: "invalid_params", message: "缺少 appId")))
            return
        }
        guard var app = AppLibrary.shared.app(id: appId) else {
            completion(WebHTTP.cors(.failure(404, code: "not_found", message: "应用未安装")))
            return
        }

        if let category = body["category"] as? String {
            app.category = category.isEmpty ? "未分类" : category
        }
        if let disabled = body["disabledCapabilities"] as? [String] {
            app.disabledCapabilities = Set(disabled)
        }
        AppLibrary.shared.update(app)
        WebAppSessionPool.shared.session(for: appId)?.refresh(app: app)
        NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        WebAccessService.shared.appendEvent(appId: "kinter.webaccess", event: "library.changed",
                                            data: ["appId": appId])
        completion(WebHTTP.cors(.json(["ok": true, "app": appsPayload().first(where: { ($0["appId"] as? String) == appId }) ?? [:]])))
    }

    private func handleDelete(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody, let appId = body["appId"] as? String else {
            completion(WebHTTP.cors(.failure(400, code: "invalid_params", message: "缺少 appId")))
            return
        }
        guard AppLibrary.shared.isInstalled(appId) else {
            completion(WebHTTP.cors(.failure(404, code: "not_found", message: "应用未安装")))
            return
        }
        WebAppSessionPool.shared.invalidate(appId)
        AppLibrary.shared.remove(appId: appId)
        NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        WebAccessService.shared.appendEvent(appId: "kinter.webaccess", event: "library.changed", data: ["appId": appId])
        completion(WebHTTP.cors(.json(["ok": true])))
    }

    // MARK: - 小程序桥接

    /// 浏览器里的小程序页面通过 /api/bridge 发调用；
    /// 与原生 BridgeMessageHandler 的分发规则保持一致：router / popup / app / auth 特判，其余走网关。
    private func handleBridge(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody,
              let appId = body["appId"] as? String,
              let module = body["module"] as? String,
              let method = body["method"] as? String else {
            completion(WebHTTP.cors(.failure(400, code: "invalid_params", message: "缺少 appId/module/method")))
            return
        }
        let callbackId = body["callbackId"] as? String ?? "cb"
        let params = body["params"] as? [String: Any] ?? [:]

        func reply(ok: Bool, data: [String: Any]? = nil, error: [String: Any]? = nil) {
            var payload: [String: Any] = ["ok": ok, "callbackId": callbackId]
            if let d = data { payload["data"] = d }
            if let e = error { payload["error"] = e }
            completion(WebHTTP.cors(.json(payload)))
        }

        // 客户端自己实现的模块（导航栈、弹窗），服务端只做兜底
        if module == "router" || module == "popup" {
            reply(ok: false, error: ["code": "handled_in_page", "message": "\(module).\(method) 由页面侧处理"])
            return
        }

        guard let session = WebAppSessionPool.shared.sessionOrCreate(for: appId) else {
            reply(ok: false, error: ["code": "app_unavailable", "message": "应用未安装或 manifest 无法解析"])
            return
        }
        WebAccessService.shared.attachEvents(to: session)

        switch module {
        case "app":
            switch method {
            case "getLaunchParams":
                let p = session.launchParams ?? [:]
                session.launchParams = nil
                reply(ok: true, data: ["params": p])
            case "canOpen":
                let target = params["appId"] as? String ?? ""
                reply(ok: true, data: ["canOpen": AppLibrary.shared.isInstalled(target)])
            case "open":
                guard let target = params["appId"] as? String, !target.isEmpty else {
                    reply(ok: false, error: ["code": "invalid_params", "message": "appId 必填"])
                    return
                }
                if AppLibrary.shared.isInstalled(target) {
                    reply(ok: true, data: ["ok": true, "openAppId": target])
                } else {
                    reply(ok: false, error: ["code": "open_failed", "message": "目标应用未安装"])
                }
            default:
                reply(ok: false, error: ["code": "method_not_found", "message": "app.\(method)"])
            }

        case "auth":
            if method == "getUserInfo" || method == "requestLogin" {
                if let user = KinterAuthManager.shared.restoreSession() {
                    reply(ok: true, data: [
                        "loggedIn": true,
                        "user": ["id": user.id, "username": user.username, "name": user.displayName]
                    ])
                } else {
                    reply(ok: true, data: ["loggedIn": false])
                }
            } else {
                reply(ok: false, error: ["code": "method_not_found", "message": "auth.\(method)"])
            }

        case "permission":
            reply(ok: false, error: ["code": "unsupported",
                                     "message": "Web 端无法弹出系统权限：请在 App 内授权后再从 Web 调用"])

        case "store":
            reply(ok: false, error: ["code": "unsupported", "message": "Web 端暂不支持小程序内商店调用"])

        default:
            // 浏览器原生采集：camera / microphone 只做授权判定，真正的采集在页面里完成
            let wantsWebNative = (params["__kinterWebNative"] as? Bool) == true
                && (module == "camera" || module == "microphone")
            DispatchQueue.main.async {
                if wantsWebNative {
                    session.gateway.authorizeWebNative(module: module, method: method) { result in
                        switch result {
                        case .success:
                            reply(ok: true, data: ["result": ["webNative": true]])
                        case .failure(let err):
                            reply(ok: false, error: err.asJSON)
                        }
                    }
                    return
                }
                session.gateway.invoke(module: module, method: method, params: params) { result in
                    switch result {
                    case .success(let value):
                        reply(ok: true, data: ["result": WebAccessService.jsonSafe(value)])
                    case .failure(let err):
                        reply(ok: false, error: err.asJSON)
                    }
                }
            }
        }
    }

    // MARK: - 设置

    private func settingsPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "launchMode": AppSettings.shared.launchMode.rawValue,
            "lastOpenedAppId": AppSettings.shared.lastOpenedAppId ?? "",
            "customAppId": AppSettings.shared.customAppId ?? "",
            "customParams": AppSettings.shared.customParams ?? "",
            "confirmInstall": AppSettings.shared.confirmInstall,
            "showWarnings": AppSettings.shared.showWarnings,
            "allowAppsAccessAccount": AppSettings.shared.allowAppsAccessAccount,
            "authServerURL": AppSettings.shared.authServerURL ?? "",
            "securityMode": SecurityMode.shared.isEnabled,
            "port": Int(settings.port),
            "autoStart": settings.autoStart,
            "running": WebAccessService.shared.isRunning,
            "baseURL": WebAccessService.shared.baseURL ?? ""
        ]
        if let url = WebAccessService.shared.accessURL { payload["accessURL"] = url }
        payload["token"] = settings.token
        return payload
    }

    private func handleSettingsUpdate(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody else {
            completion(WebHTTP.cors(.failure(400, code: "invalid_params", message: "请求体必须是 JSON")))
            return
        }
        var portChanged = false

        if let raw = body["launchMode"] as? String, let mode = LaunchMode(rawValue: raw) {
            AppSettings.shared.launchMode = mode
        }
        if let v = body["confirmInstall"] as? Bool { AppSettings.shared.confirmInstall = v }
        if let v = body["showWarnings"] as? Bool { AppSettings.shared.showWarnings = v }
        if let v = body["allowAppsAccessAccount"] as? Bool { AppSettings.shared.allowAppsAccessAccount = v }
        if let v = body["authServerURL"] as? String {
            AppSettings.shared.authServerURL = v.isEmpty ? nil : v
        }
        if let v = body["customAppId"] as? String {
            AppSettings.shared.customAppId = v.isEmpty ? nil : v
        }
        if let v = body["customParams"] as? String {
            AppSettings.shared.customParams = v.isEmpty ? nil : v
        }
        if let v = body["securityMode"] as? Bool {
            SecurityMode.shared.isEnabled = v
        }
        if let v = body["autoStart"] as? Bool {
            settings.autoStart = v
        }
        if let raw = body["port"] as? Int, raw > 0,
           let p = UInt16(exactly: raw), WebAccessSettings.portRange.contains(p) {
            if p != settings.port { portChanged = true }
            settings.port = p
        }

        // 端口被占用时先探出真正能用的端口，回包里的 newURL 才是准的
        if portChanged {
            let resolved = WebAccessService.shared.nextAvailablePort(startingAt: settings.port)
            if resolved != settings.port {
                NSLog("[WebAccess] 端口 %d 被占用，改用 %d", Int(settings.port), Int(resolved))
                settings.port = resolved
            }
        }

        let payload = settingsPayload()
        // 端口改了要以新端口算地址，否则提示的还是旧地址
        let newURL: String
        if portChanged, let url = LocalNetworkInfo.baseURL(port: settings.port) {
            newURL = url
        } else {
            newURL = WebAccessService.shared.baseURL ?? ""
        }
        completion(WebHTTP.cors(.json(["ok": true, "settings": payload, "portChanged": portChanged,
                                       "newURL": newURL])))

        // 端口改了要重启服务。等响应先发出去，再换端口，避免当前连接被掐断。
        if portChanged {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.4) {
                try? WebAccessService.shared.restart(withPort: self.settings.port)
            }
        }
    }

    // MARK: - 商店

    private func storePayload() -> [String: Any] {
        let manager = StoreManager.shared
        let sources: [[String: Any]] = manager.sources.map { s in
            [
                "url": s.url,
                "name": s.name,
                "lastFetchedAt": s.lastFetchedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "lastError": s.lastError ?? ""
            ]
        }
        // 聚合所有源里缓存的条目
        var entries: [[String: Any]] = []
        for (sourceURL, index) in manager.cachedIndices {
            for app in index.apps {
                var item: [String: Any] = [
                    "appId": app.appId,
                    "name": app.name,
                    "version": app.version,
                    "subtitle": app.subtitle ?? "",
                    "description": app.description ?? "",
                    "category": app.category ?? "",
                    "price": app.price ?? 0,
                    "downloadURL": app.downloadURL,
                    "source": sourceURL,
                    "sourceName": index.name,
                    "installed": AppLibrary.shared.isInstalled(app.appId)
                ]
                if let existing = AppLibrary.shared.app(id: app.appId) {
                    item["updateAvailable"] = manager.hasUpdate(for: existing) != nil
                } else {
                    item["updateAvailable"] = false
                }
                if let icon = app.iconURL { item["iconURL"] = icon }
                entries.append(item)
            }
        }
        entries.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        return ["sources": sources, "apps": entries]
    }

    private func handleStoreAddSource(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody, let url = body["url"] as? String, !url.isEmpty else {
            completion(WebHTTP.cors(.failure(400, code: "invalid_params", message: "缺少 url")))
            return
        }
        do {
            try StoreManager.shared.addSource(url: url)
            completion(WebHTTP.cors(.json(["ok": true, "store": storePayload()])))
        } catch {
            completion(WebHTTP.cors(.failure(400, code: "invalid_source", message: error.localizedDescription)))
        }
    }

    private func handleStoreRemoveSource(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody, let url = body["url"] as? String else {
            completion(WebHTTP.cors(.failure(400, code: "invalid_params", message: "缺少 url")))
            return
        }
        StoreManager.shared.removeSource(url: url)
        completion(WebHTTP.cors(.json(["ok": true, "store": storePayload()])))
    }

    private func handleStoreRefresh(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        StoreManager.shared.refreshAll {
            completion(WebHTTP.cors(.json(["ok": true, "store": self.storePayload()])))
        }
    }

    private func handleStoreInstall(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        guard let body = request.jsonBody, let appId = body["appId"] as? String else {
            completion(WebHTTP.cors(.failure(400, code: "invalid_params", message: "缺少 appId")))
            return
        }
        let manager = StoreManager.shared
        var target: StoreApp?
        for (_, index) in manager.cachedIndices {
            if let a = index.apps.first(where: { $0.appId == appId }) { target = a; break }
        }
        guard let app = target else {
            completion(WebHTTP.cors(.failure(404, code: "not_found", message: "源里没有这个应用，先刷新商店")))
            return
        }
        manager.downloadAndInstall(app) { result in
            switch result {
            case .success(let installed):
                NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
                WebAccessService.shared.appendEvent(appId: "kinter.webaccess", event: "library.changed",
                                                    data: ["appId": installed.appId])
                completion(WebHTTP.cors(.json(["ok": true, "appId": installed.appId,
                                               "name": installed.name, "version": installed.version,
                                               "runURL": "/run?appId=\(installed.appId)"])))
            case .failure(let error):
                completion(WebHTTP.cors(.failure(400, code: "install_failed",
                                                 message: error.localizedDescription)))
            }
        }
    }
}
