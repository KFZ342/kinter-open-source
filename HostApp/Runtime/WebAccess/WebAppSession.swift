import Foundation

/// Web 端运行一个小程序时的会话：与原生 Runner 一样，持有独立的网关、manifest、存储与启动参数。
/// 每个 appId 一个会话，重复打开同一个应用时复用（对应原生「实例池化」的思路）。
final class WebAppSession {

    let appId: String
    private(set) var app: InstalledApp
    let gateway = CapabilityGateway()
    let store = AppStore()
    private(set) var manifest: MiniAppManifest?
    /// 启动参数（app.getLaunchParams 取一次即清）
    var launchParams: [String: Any]?

    /// 事件出口，由 WebAccessService 注入
    var onEvent: ((String, Any) -> Void)?

    init(app: InstalledApp) throws {
        self.appId = app.appId
        self.app = app
        guard let data = try? Data(contentsOf: app.manifestURL),
              let parsed = try? ManifestParser.parse(data: data) else {
            throw GatewayError.invalidParams("manifest.json 缺失或无法解析")
        }
        self.manifest = parsed
        gateway.setManifest(parsed)
        gateway.setDisabledCapabilities(app.disabledCapabilities)
        gateway.bindEmitters { [weak self] event, payload in
            self?.onEvent?(event, payload)
        }
    }

    func refresh(app updated: InstalledApp) {
        app = updated
        gateway.setDisabledCapabilities(updated.disabledCapabilities)
    }
}

/// 会话池：按 appId 缓存运行中的 Web 小程序会话。
final class WebAppSessionPool {

    static let shared = WebAppSessionPool()

    private var sessions: [String: WebAppSession] = [:]
    private let lock = NSLock()

    private init() {}

    func session(for appId: String) -> WebAppSession? {
        lock.lock(); defer { lock.unlock() }
        return sessions[appId]
    }

    /// 取或新建。应用未安装 / manifest 损坏时返回 nil。
    func sessionOrCreate(for appId: String) -> WebAppSession? {
        if let s = session(for: appId) { return s }
        guard let app = AppLibrary.shared.app(id: appId),
              let s = try? WebAppSession(app: app) else { return nil }
        lock.lock()
        if let existing = sessions[appId] {
            lock.unlock()
            return existing
        }
        sessions[appId] = s
        lock.unlock()
        return s
    }

    func invalidate(_ appId: String) {
        lock.lock(); defer { lock.unlock() }
        sessions.removeValue(forKey: appId)
    }

    func invalidateAll() {
        lock.lock(); defer { lock.unlock() }
        sessions.removeAll()
    }
}
