import Foundation

/// 应用库：管理已安装小程序的持久化与目录操作。
final class AppLibrary {
    static let shared = AppLibrary()

    private(set) var apps: [InstalledApp] = []
    private let queue = DispatchQueue(label: "app.library", qos: .userInitiated)

    private var rootDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Apps", isDirectory: true)
    }

    private var indexURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("library.json")
    }

    private init() {
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([InstalledApp].self, from: data) else {
            apps = []
            return
        }
        apps = list
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(apps) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - 查询

    func app(id: String) -> InstalledApp? { apps.first { $0.appId == id } }

    func isInstalled(_ appId: String) -> Bool { app(id: appId) != nil }

    /// 全部分类（去重，保持稳定顺序）
    var categories: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for a in apps where !seen.contains(a.category) {
            seen.insert(a.category)
            out.append(a.category)
        }
        return out.sorted()
    }

    // MARK: - 变更

    func add(_ app: InstalledApp) {
        queue.sync {
            apps.removeAll { $0.appId == app.appId }
            apps.append(app)
            apps.sort { $0.installedAt > $1.installedAt }
            persist()
        }
    }

    func update(_ app: InstalledApp) {
        queue.sync {
            guard let i = apps.firstIndex(where: { $0.appId == app.appId }) else { return }
            apps[i] = app
            persist()
        }
    }

    func remove(appId: String) {
        queue.sync {
            guard let app = apps.first(where: { $0.appId == appId }) else { return }
            try? FileManager.default.removeItem(at: app.directory)
            apps.removeAll { $0.appId == appId }
            persist()
        }
    }

    /// 切换某能力对该应用的禁用状态
    func setCapability(_ capability: String, enabled: Bool, for appId: String) {
        queue.sync {
            guard let i = apps.firstIndex(where: { $0.appId == appId }) else { return }
            if enabled {
                apps[i].disabledCapabilities.remove(capability)
            } else {
                apps[i].disabledCapabilities.insert(capability)
            }
            persist()
        }
    }

    // MARK: - 收藏 / 评分 / 使用统计

    /// 设置收藏状态
    func setFavorite(_ favorite: Bool, for appId: String) {
        queue.sync {
            guard let i = apps.firstIndex(where: { $0.appId == appId }) else { return }
            apps[i].isFavorite = favorite
            persist()
        }
        notifyChange()
    }

    /// 切换收藏，返回切换后的状态
    @discardableResult
    func toggleFavorite(appId: String) -> Bool {
        var now = false
        queue.sync {
            guard let i = apps.firstIndex(where: { $0.appId == appId }) else { return }
            apps[i].isFavorite.toggle()
            now = apps[i].isFavorite
            persist()
        }
        notifyChange()
        return now
    }

    /// 设置评分（0-5，0 表示清除评分）
    func setRating(_ rating: Int, for appId: String) {
        let clamped = max(0, min(5, rating))
        queue.sync {
            guard let i = apps.firstIndex(where: { $0.appId == appId }) else { return }
            apps[i].rating = clamped
            persist()
        }
        notifyChange()
    }

    /// 记录一次打开
    func recordLaunch(appId: String) {
        queue.sync {
            guard let i = apps.firstIndex(where: { $0.appId == appId }) else { return }
            apps[i].launchCount += 1
            apps[i].lastOpenedAt = Date()
            persist()
        }
    }

    /// 累计使用时长（秒）
    func addUsage(appId: String, seconds: TimeInterval) {
        guard seconds > 0 else { return }
        queue.sync {
            guard let i = apps.firstIndex(where: { $0.appId == appId }) else { return }
            apps[i].totalUsageSeconds += seconds
            persist()
        }
    }

    /// 收藏的应用（按名称排序）
    var favoriteApps: [InstalledApp] {
        apps.filter { $0.isFavorite }.sorted { $0.name < $1.name }
    }

    /// 全库累计打开次数
    var totalLaunchCount: Int {
        apps.reduce(0) { $0 + $1.launchCount }
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        }
    }
}
