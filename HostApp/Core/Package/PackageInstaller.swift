import Foundation

/// 安装结果。
struct InstallResult {
    let app: InstalledApp
    let warnings: [String]
}

/// 安装错误。
enum InstallError: LocalizedError {
    case zipInvalid(String)
    case missingManifest
    case invalidManifest(String)
    case missingEntry(String)
    case unsafePath(String)
    case alreadyInstalled(String)
    case writeFailed(String)
    case packageTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .zipInvalid(let s):      return "安装包无效：\(s)"
        case .missingManifest:        return "安装包缺少 manifest.json"
        case .invalidManifest(let s): return "manifest 解析失败：\(s)"
        case .missingEntry(let s):    return "安装包缺少入口页面：\(s)"
        case .unsafePath(let s):      return "安装包含非法路径：\(s)"
        case .alreadyInstalled(let s):return "应用已安装：\(s)"
        case .writeFailed(let s):     return "写入失败：\(s)"
        case .packageTooLarge(let s): return "安装包过大：\(s)"
        }
    }
}

/// ZIP 安装器：校验 → 解压 → 注册到应用库。
final class PackageInstaller {
    static let shared = PackageInstaller()
    private init() {}

    /// 安装一个 ZIP 包。overwrite=false 时若已存在则报错。
    func install(zipURL: URL, overwrite: Bool = false, category: String = "未分类") throws -> InstallResult {
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

        // 1. 路径安全 + 结构检查 + ZIP 炸弹预检
        var warnings: [String] = []
        var manifestEntry: ZipArchive.Entry?
        var allPaths: Set<String> = []
        var totalUncompressed = 0

        let maxTotalBytes = 100 * 1024 * 1024      // 解压后总量上限 100MB
        let maxEntryCount = 2000                    // 条目数上限，防海量小文件拖垮文件系统

        for e in archive.entries {
            if e.path.contains("..") || e.path.hasPrefix("/") {
                throw InstallError.unsafePath(e.path)
            }
            let lower = e.path.lowercased()
            if lower.hasSuffix(".app/")
                || lower.hasSuffix(".appx/")
                || lower.hasSuffix(".exe/")
                || lower.hasSuffix(".dylib") {
                warnings.append("包含非网页资源：\(e.path)")
            }
            if lower.hasSuffix("manifest.json") { manifestEntry = e }
            allPaths.insert(e.path)

            // ZIP 炸弹防护：按中央目录声明的解压大小累计，超限直接拒绝
            totalUncompressed += e.uncompressedSize
            if totalUncompressed > maxTotalBytes {
                throw InstallError.packageTooLarge("解压总量超过 \(maxTotalBytes / (1024 * 1024))MB，疑似炸弹包")
            }
        }
        if archive.entries.count > maxEntryCount {
            throw InstallError.packageTooLarge("文件条目超过 \(maxEntryCount) 个")
        }

        guard let mEntry = manifestEntry else { throw InstallError.missingManifest }

        // 2. 解析 manifest
        let manifestData: Data
        do { manifestData = try archive.extract(mEntry) }
        catch { throw InstallError.invalidManifest(error.localizedDescription) }

        let manifest: MiniAppManifest
        do { manifest = try ManifestParser.parse(data: manifestData) }
        catch { throw InstallError.invalidManifest("\(error)") }

        // 3. 入口页面：按 manifest.pages[0] 校验（必须在 zip 中存在）
        guard let firstPage = manifest.pages.first, !firstPage.isEmpty else {
            throw InstallError.missingEntry("manifest.pages 为空")
        }
        var entryRel = firstPage
        if !entryRel.hasSuffix(".html") { entryRel += ".html" }

        // 计算 zip 根前缀（与后面解压逻辑一致）
        let zipPrefix = zipRootPrefix(of: archive, manifestPath: mEntry.path)
        let entryInZip = zipPrefix + entryRel

        if !allPaths.contains(entryInZip) {
            // 兼容：有些打包工具会带上 ./ 前缀
            let alt = "./" + entryInZip
            if !allPaths.contains(alt) {
                throw InstallError.missingEntry(entryRel)
            }
        }

        // 4. 重名检查
        if AppLibrary.shared.isInstalled(manifest.appId) && !overwrite {
            throw InstallError.alreadyInstalled(manifest.name)
        }

        // 5. 计算解压基路径（如果 zip 里有一层根目录，去掉它）
        let prefix = zipRootPrefix(of: archive, manifestPath: mEntry.path)

        // 6. 落盘
        let iconName = manifest.icon
        let app = InstalledApp(appId: manifest.appId,
                               name: manifest.name,
                               version: manifest.version,
                               installedAt: Date(),
                               category: category,
                               disabledCapabilities: [],
                               iconFileName: iconName)
        let dest = app.directory

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            throw InstallError.writeFailed("创建目录失败")
        }

        var writtenBytes = 0
        for e in archive.entries {
            // 跳过目录项
            if e.path.hasSuffix("/") { continue }
            var rel = e.path
            if !prefix.isEmpty && rel.hasPrefix(prefix) { rel = String(rel.dropFirst(prefix.count)) }
            if rel.isEmpty { continue }
            let target = dest.appendingPathComponent(rel)
            // 二次路径校验（防 ..）
            guard target.standardizedFileURL.path.hasPrefix(dest.standardizedFileURL.path) else {
                throw InstallError.unsafePath(e.path)
            }
            do {
                let bytes = try archive.extract(e)
                // 实际解压量累计（中央目录声明可能被伪造）
                writtenBytes += bytes.count
                if writtenBytes > maxTotalBytes {
                    throw InstallError.packageTooLarge("实际解压量超过 \(maxTotalBytes / (1024 * 1024))MB，已中止")
                }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try bytes.write(to: target, options: .atomic)
            } catch let err as InstallError {
                throw err
            } catch {
                throw InstallError.writeFailed(e.path)
            }
        }

        // 6.5 校验图标
        if let iconName = manifest.icon {
            let iconPath = dest.appendingPathComponent(iconName)
            if !FileManager.default.fileExists(atPath: iconPath.path) {
                warnings.append("manifest 声明了图标 \(iconName)，但安装包中不存在")
            }
        }

        // 7. 未知能力提示
        for (cap, _) in manifest.capabilities ?? [:] {
            if !PermissionCatalog.isKnown(cap) {
                warnings.append("未知能力：\(cap)（将被网关拒绝）")
            }
        }

        // 8. 注册
        AppLibrary.shared.add(app)

        return InstallResult(app: app, warnings: warnings)
    }

    /// 找出 zip 内部的公共前缀（如 "myapp/"），便于去掉外层文件夹。
    private func zipRootPrefix(of archive: ZipArchive, manifestPath: String) -> String {
        guard let slash = manifestPath.lastIndex(of: "/") else { return "" }
        return String(manifestPath[manifestPath.startIndex...slash])
    }
}
