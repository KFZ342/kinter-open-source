import AppIntents
import Foundation

/// 快捷指令里可选的小程序实体。
/// 用户在快捷指令 App 里会看到一个下拉列表，列出所有已安装应用。
struct MiniAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "小程序"
    static var defaultQuery = MiniAppEntityQuery()

    var id: String   // appId
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(app: InstalledApp) {
        self.id = app.appId
        self.name = app.name
    }
}

/// 查询已安装的小程序列表。
struct MiniAppEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MiniAppEntity] {
        AppLibrary.shared.apps
            .filter { identifiers.contains($0.appId) }
            .map { MiniAppEntity(app: $0) }
    }

    func suggestedEntities() async throws -> [MiniAppEntity] {
        AppLibrary.shared.apps.map { MiniAppEntity(app: $0) }
    }

    func defaultResult() async -> MiniAppEntity? {
        AppLibrary.shared.apps.first.map { MiniAppEntity(app: $0) }
    }
}
