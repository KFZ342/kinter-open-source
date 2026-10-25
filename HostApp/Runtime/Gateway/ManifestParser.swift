import Foundation

struct MiniAppManifest: Codable {
    struct CapabilityDecl: Codable {
        var level: String
        var reason: String?
        var scope: String?
    }
    struct Window: Codable {
        var navigationStyle: String?
        var backgroundColor: String?
    }

    var appId: String
    var version: String
    var name: String
    var minHostVersion: String?
    var pages: [String]
    var capabilities: [String: CapabilityDecl]?
    var window: Window?
    /// 图标文件名（相对包根目录），如 "icon.png"
    var icon: String?
    /// 售价（元）。nil / 0 / 缺省 = 免费；>0 = 付费小程序
    var price: Double?

    func declares(_ capability: String) -> Bool {
        guard let capabilities = capabilities else { return false }
        return capabilities[capability] != nil
    }
}

enum ManifestParser {
    static func parse(data: Data) throws -> MiniAppManifest {
        do {
            return try JSONDecoder().decode(MiniAppManifest.self, from: data)
        } catch {
            throw GatewayError.invalidParams("manifest decode failed: \(error)")
        }
    }
}
