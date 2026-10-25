import Foundation
import CryptoKit

/// 商店管理器：管理源列表、拉取索引、聚合应用、检查更新。
final class StoreManager {
    static let shared = StoreManager()

    private let defaults = UserDefaults.standard
    private let sourcesKey = "store.sources"
    private let cacheKey = "store.cache"

    /// 已添加的源
    private(set) var sources: [StoreSource] = []
    /// 源 URL -> 拉取到的索引
    private(set) var cachedIndices: [String: StoreIndex] = [:]

    private let queue = DispatchQueue(label: "store.manager")

    private init() {
        loadSources()
        loadCache()
    }

    // MARK: - 源管理

    private func loadSources() {
        guard let data = defaults.data(forKey: sourcesKey),
              let list = try? JSONDecoder().decode([StoreSource].self, from: data) else {
            sources = []
            return
        }
        sources = list
    }

    private func persistSources() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: sourcesKey)
    }

    private func loadCache() {
        guard let data = defaults.data(forKey: cacheKey),
              let map = try? JSONDecoder().decode([String: StoreIndex].self, from: data) else {
            cachedIndices = [:]
            return
        }
        cachedIndices = map
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(cachedIndices) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    func addSource(url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // 相对路径（如 /store/alice/index.json）自动拼认证服务器地址
        guard let resolved = Self.resolveURL(trimmed) else {
            throw StoreError.invalidURL
        }
        let normalized = resolved.absoluteString
        guard !sources.contains(where: { $0.url == normalized }) else {
            throw StoreError.duplicateSource
        }
        sources.append(StoreSource(url: normalized))
        persistSources()
    }

    /// 统一解析商店 URL：绝对地址直接用；相对路径拼认证服务器 base。
    static func resolveURL(_ urlStr: String) -> URL? {
        let trimmed = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        let base = AppSettings.shared.authServerURL ?? KinterAuthManager.defaultServerURL
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        let joined = trimmed.hasPrefix("/") ? trimmedBase + trimmed : trimmedBase + "/" + trimmed
        return URL(string: joined)
    }

    func removeSource(url: String) {
        sources.removeAll { $0.url == url }
        cachedIndices.removeValue(forKey: url)
        persistSources()
        persistCache()
    }

    // MARK: - 拉取

    /// 拉取所有源。每个源独立处理，失败不影响其他源。
    func refreshAll(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for i in sources.indices {
            let src = sources[i]
            group.enter()
            fetchIndex(url: src.url) { result in
                self.queue.sync {
                    switch result {
                    case .success(let index):
                        self.cachedIndices[src.url] = index
                        self.sources[i].name = index.name
                        self.sources[i].lastFetchedAt = Date()
                        self.sources[i].lastError = nil
                    case .failure(let err):
                        self.sources[i].lastError = err.localizedDescription
                    }
                    self.persistSources()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.persistCache()
            completion()
        }
    }

    private func fetchIndex(url: String, completion: @escaping (Result<StoreIndex, Error>) -> Void) {
        guard let u = Self.resolveURL(url) else {
            completion(.failure(StoreError.invalidURL))
            return
        }
        // 加时间戳绕过 HTTP 缓存
        var comps = URLComponents(url: u, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "_t", value: String(Int(Date().timeIntervalSince1970))))
        comps?.queryItems = items
        let finalURL = comps?.url ?? u

        var req = URLRequest(url: finalURL)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data else {
                completion(.failure(StoreError.fetchFailed))
                return
            }
            do {
                let index = try JSONDecoder().decode(StoreIndex.self, from: data)
                completion(.success(index))
            } catch {
                completion(.failure(StoreError.parseFailed(error.localizedDescription)))
            }
        }.resume()
    }

    // MARK: - 聚合

    /// 所有源里的应用，去重（同 appId 保留版本号更高的）
    var allApps: [StoreApp] {
        var merged: [String: StoreApp] = [:]
        for (_, index) in cachedIndices {
            for app in index.apps {
                if let existing = merged[app.appId] {
                    if compareVersion(app.version, existing.version) > 0 {
                        merged[app.appId] = app
                    }
                } else {
                    merged[app.appId] = app
                }
            }
        }
        return Array(merged.values).sorted { $0.name < $1.name }
    }

    /// 分类分组
    var appsByCategory: [(category: String, apps: [StoreApp])] {
        let grouped = Dictionary(grouping: allApps) { $0.category ?? "其他" }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.name < $1.name }) }
    }

    /// 检查某应用是否有更新
    func hasUpdate(for installed: InstalledApp) -> StoreApp? {
        guard let remote = allApps.first(where: { $0.appId == installed.appId }) else { return nil }
        return compareVersion(remote.version, installed.version) > 0 ? remote : nil
    }

    /// 语义化版本比较：1.0.0 vs 1.0.1
    func compareVersion(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }

    // MARK: - 下载与安装

    /// 下载 ZIP 并安装。校验 SHA256。付费小程序需先购买（PurchaseManager 校验）。
    func downloadAndInstall(_ app: StoreApp, completion: @escaping (Result<InstalledApp, Error>) -> Void) {
        // 付费门：付费小程序未购买则拦截
        if let price = app.price, price > 0,
           !PurchaseManager.shared.isPurchased(appId: app.appId, price: price) {
            DispatchQueue.main.async {
                completion(.failure(StoreError.requiresPurchase(price: price)))
            }
            return
        }

        guard let url = Self.resolveURL(app.downloadURL) else {
            completion(.failure(StoreError.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 60

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfig.urlCache = nil
        let session = URLSession(configuration: sessionConfig)

        session.downloadTask(with: req) { tmpURL, resp, err in
            if let err = err {
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let tmp = tmpURL else {
                DispatchQueue.main.async { completion(.failure(StoreError.downloadFailed)) }
                return
            }

            // 移到临时目录（带扩展名，方便 unzip 判断）
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("store_\(UUID().uuidString).zip")
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
            } catch {
                completion(.failure(error))
                return
            }

            // SHA256 校验
            if let expected = app.sha256, !expected.isEmpty {
                guard let actual = Self.sha256(of: dest),
                      actual.lowercased() == expected.lowercased() else {
                    try? FileManager.default.removeItem(at: dest)
                    DispatchQueue.main.async {
                        completion(.failure(StoreError.checksumMismatch))
                    }
                    return
                }
            }

            // 安装
            do {
                let result = try PackageInstaller.shared.install(
                    zipURL: dest,
                    overwrite: true,
                    category: app.category ?? "未分类"
                )
                // 合并付费信息（manifest 可能没声明，以商店条目为准）
                var installed = result.app
                if let price = app.price, price > 0 {
                    installed.price = price
                    installed.paid = PurchaseManager.shared.isPurchased(appId: app.appId, price: price)
                }
                AppLibrary.shared.add(installed)   // add 本身是 upsert 语义，覆盖无价格记录
                try? FileManager.default.removeItem(at: dest)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
                    completion(.success(installed))
                }
            } catch {
                try? FileManager.default.removeItem(at: dest)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    /// 计算文件 SHA256
    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 用 CryptoKit 的 SHA256（import CryptoKit）
        var hash = SHA256()
        hash.update(data: data)
        let digest = hash.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 错误

enum StoreError: LocalizedError {
    case invalidURL
    case duplicateSource
    case fetchFailed
    case parseFailed(String)
    case downloadFailed
    case checksumMismatch
    case requiresPurchase(price: Double)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "URL 无效"
        case .duplicateSource:     return "这个源已经添加过了"
        case .fetchFailed:         return "拉取源失败"
        case .parseFailed(let s):  return "源格式错误: \(s)"
        case .downloadFailed:      return "下载失败"
        case .checksumMismatch:    return "文件校验失败，可能被篡改"
        case .requiresPurchase(let price):
            return String(format: "这是付费小程序（¥%.2f），购买后才能安装", price)
        }
    }
}
