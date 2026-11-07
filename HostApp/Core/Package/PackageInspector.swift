import Foundation

/// 安装前预览信息。只读，不写磁盘。
struct PackagePreview {
    let manifest: MiniAppManifest
    /// 高危能力（critical 档）：通讯录、健康、麦克风等
    let sensitiveCapabilities: [String]
    /// 中危能力（standard 档）：相机、定位、相册等
    let standardCapabilities: [String]
    /// 普通能力（L0 / network 档）
    let normalCapabilities: [String]
    /// 未知能力（网关会拒绝）
    let unknownCapabilities: [String]

    var totalCapabilityCount: Int {
        sensitiveCapabilities.count + standardCapabilities.count + normalCapabilities.count
    }
}

/// 安装前检查器：从 ZIP 里只提取 manifest.json 并解析，不做任何落盘。
enum PackageInspector {
    static func inspect(zipURL: URL) throws -> PackagePreview {
        let data: Data
        do {
            data = try Data(contentsOf: zipURL)
        } catch {
            throw InstallError.zipInvalid("无法读取文件")
        }

        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch {
            throw InstallError.zipInvalid(error.localizedDescription)
        }

        guard let mEntry = archive.entries.first(where: { $0.path.lowercased().hasSuffix("manifest.json") }) else {
            throw InstallError.missingManifest
        }

        let manifestData: Data
        do {
            manifestData = try archive.extract(mEntry)
        } catch {
            throw InstallError.invalidManifest(error.localizedDescription)
        }

        let manifest: MiniAppManifest
        do {
            manifest = try ManifestParser.parse(data: manifestData)
        } catch {
            throw InstallError.invalidManifest("\(error)")
        }

        var sensitive: [String] = []
        var standard: [String] = []
        var normal: [String] = []
        var unknown: [String] = []

        for cap in (manifest.capabilities ?? [:]).keys.sorted() {
            guard PermissionCatalog.isKnown(cap) else {
                unknown.append(cap)
                continue
            }
            if let tier = SecurityPolicy.tier(of: cap) {
                switch tier {
                case .critical: sensitive.append(cap)
                case .standard: standard.append(cap)
                case .network:  normal.append(cap)
                case .benign:   normal.append(cap)
                }
            } else {
                normal.append(cap)
            }
        }

        return PackagePreview(
            manifest: manifest,
            sensitiveCapabilities: sensitive,
            standardCapabilities: standard,
            normalCapabilities: normal,
            unknownCapabilities: unknown
        )
    }
}
