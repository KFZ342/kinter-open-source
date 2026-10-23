import Foundation

/// 一个已安装的小程序。持久化到 Documents/library.json。
struct InstalledApp: Codable, Identifiable, Equatable {
    let appId: String
    let name: String
    let version: String
    let installedAt: Date
    /// 用户可自定义的分类，默认 "未分类"
    var category: String
    /// 被用户禁用的能力 ID 集合
    var disabledCapabilities: Set<String>
    /// 图标文件名（相对应用目录），nil 表示无图标
    var iconFileName: String?
    /// 是否由 AI 生成
    var isAIGenerated: Bool = false
    /// AI 生成时的原始描述，用于后续迭代
    var generationPrompt: String?

    var id: String { appId }

    /// 应用代码目录（不进 Files 浏览）
    var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Apps", isDirectory: true)
                   .appendingPathComponent(appId, isDirectory: true)
    }

    /// 应用用户数据目录（可在 Files app 中浏览）
    /// 与代码目录隔离，卸载时不自动删除（除非用户主动清）
    var dataDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Data", isDirectory: true)
                   .appendingPathComponent(appId, isDirectory: true)
    }

    /// 确保数据目录存在
    func ensureDataDirectory() {
        try? FileManager.default.createDirectory(at: dataDirectory,
                                                 withIntermediateDirectories: true)
    }

    /// 入口页面：按 manifest.pages[0] 解析，兼容单页应用的 "index" 写法。
    /// 若无法解析则退化为根目录 index.html。
    var entryURL: URL {
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? ManifestParser.parse(data: data),
              let first = m.pages.first, !first.isEmpty else {
            return directory.appendingPathComponent("index.html")
        }
        var rel = first
        if !rel.hasSuffix(".html") { rel += ".html" }
        return directory.appendingPathComponent(rel)
    }

    /// manifest
    var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    /// 图标完整路径，若无图标返回 nil
    var iconURL: URL? {
        guard let name = iconFileName else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    init(appId: String, name: String, version: String, installedAt: Date,
         category: String, disabledCapabilities: Set<String>,
         iconFileName: String? = nil, isAIGenerated: Bool = false,
         generationPrompt: String? = nil) {
        self.appId = appId
        self.name = name
        self.version = version
        self.installedAt = installedAt
        self.category = category
        self.disabledCapabilities = disabledCapabilities
        self.iconFileName = iconFileName
        self.isAIGenerated = isAIGenerated
        self.generationPrompt = generationPrompt
    }

    // 容错解码：旧 library.json 没有 isAIGenerated / generationPrompt 字段
    enum CodingKeys: String, CodingKey {
        case appId, name, version, installedAt, category
        case disabledCapabilities, iconFileName
        case isAIGenerated, generationPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appId = try c.decode(String.self, forKey: .appId)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        installedAt = try c.decode(Date.self, forKey: .installedAt)
        category = (try? c.decode(String.self, forKey: .category)) ?? "未分类"
        disabledCapabilities = (try? c.decode(Set<String>.self, forKey: .disabledCapabilities)) ?? []
        iconFileName = try? c.decodeIfPresent(String.self, forKey: .iconFileName)
        isAIGenerated = (try? c.decode(Bool.self, forKey: .isAIGenerated)) ?? false
        generationPrompt = try? c.decodeIfPresent(String.self, forKey: .generationPrompt)
    }
}
