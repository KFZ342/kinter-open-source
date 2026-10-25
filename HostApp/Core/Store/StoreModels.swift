import Foundation

// MARK: - 源索引（index.json）

/// 一个应用商店源。对应 index.json 的顶层结构。
struct StoreIndex: Codable {
    let name: String
    let identifier: String?
    let subtitle: String?
    let iconURL: String?
    let website: String?
    let apps: [StoreApp]
}

/// 源里的一个应用条目。
struct StoreApp: Codable, Identifiable {
    let appId: String
    let name: String
    let version: String
    let subtitle: String?
    let description: String?
    let category: String?
    let iconURL: String?
    let downloadURL: String
    let size: Int?
    let sha256: String?
    let minHostVersion: String?
    /// 售价（元）。nil / 0 = 免费；>0 = 付费小程序
    let price: Double?
    /// 货币代码，默认 CNY
    let currency: String?

    var id: String { appId }
}

// MARK: - 用户配置的源

/// 用户添加的一个源。持久化到 UserDefaults。
struct StoreSource: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String          // index.json 的完整 URL
    var name: String         // 显示名，首次拉取后从 StoreIndex 填充
    var addedAt: Date
    var lastFetchedAt: Date?
    var lastError: String?

    init(url: String, name: String = "未命名源") {
        self.id = UUID()
        self.url = url
        self.name = name
        self.addedAt = Date()
        self.lastFetchedAt = nil
        self.lastError = nil
    }
}

// MARK: - 拉取结果

/// 一个源的拉取状态。
enum StoreFetchState {
    case idle
    case loading
    case loaded(StoreIndex)
    case failed(String)
}

/// 聚合后的应用条目：带上来源信息。
struct StoreAppEntry: Identifiable {
    let app: StoreApp
    let sourceId: UUID
    let sourceName: String

    var id: String { "\(sourceId.uuidString)-\(app.appId)" }
}
