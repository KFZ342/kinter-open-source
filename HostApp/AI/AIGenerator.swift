import Foundation
import UIKit

/// AI 生成结果解析器 + 打包器。
/// 把模型返回的 JSON 文本变成可安装的小程序 ZIP。
final class AIGenerator {

    struct GeneratedApp {
        let name: String
        let appId: String
        let version: String
        let category: String
        let description: String
        let pages: [String]
        let capabilities: [String: Any]
        let files: [String: String]
    }

    enum GenError: LocalizedError {
        case noJSON
        case invalidJSON(String)
        case missingField(String)
        case noFiles
        case noIndexHTML
        case unsafePath(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noJSON:              return "模型输出中找不到 JSON"
            case .invalidJSON(let s):  return "JSON 解析失败: \(s)"
            case .missingField(let f): return "缺少字段: \(f)"
            case .noFiles:             return "没有生成任何文件"
            case .noIndexHTML:         return "缺少 index.html"
            case .unsafePath(let p):   return "非法路径: \(p)"
            case .writeFailed(let s):  return "写入失败: \(s)"
            }
        }
    }

    /// 从模型输出里提取 JSON。容忍 markdown 代码块包裹。
    static func extractJSON(from text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 去掉 ```json ... ``` 包裹
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let closing = s.range(of: "```", options: .backwards) {
                s = String(s[..<closing.lowerBound])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 找第一个 { 和最后一个 }
        guard let start = s.firstIndex(of: "{"),
              let end = s.lastIndex(of: "}") else { return nil }
        return String(s[start...end])
    }

    /// 解析模型输出为 GeneratedApp。
    static func parse(_ raw: String) throws -> GeneratedApp {
        guard let jsonStr = extractJSON(from: raw) else { throw GenError.noJSON }
        guard let data = jsonStr.data(using: .utf8) else { throw GenError.invalidJSON("编码失败") }
        let obj: [String: Any]
        do {
            obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw GenError.invalidJSON(error.localizedDescription)
        }

        guard let name = obj["name"] as? String, !name.isEmpty else {
            throw GenError.missingField("name")
        }
        guard let appId = obj["appId"] as? String, !appId.isEmpty else {
            throw GenError.missingField("appId")
        }
        guard let filesRaw = obj["files"] as? [String: String], !filesRaw.isEmpty else {
            throw GenError.noFiles
        }
        guard filesRaw["index.html"] != nil else { throw GenError.noIndexHTML }

        // 路径安全校验
        for path in filesRaw.keys {
            if path.contains("..") || path.hasPrefix("/") {
                throw GenError.unsafePath(path)
            }
        }

        return GeneratedApp(
            name: name,
            appId: appId,
            version: (obj["version"] as? String) ?? "1.0.0",
            category: (obj["category"] as? String) ?? "工具",
            description: (obj["description"] as? String) ?? "",
            pages: (obj["pages"] as? [String]) ?? ["index"],
            capabilities: (obj["capabilities"] as? [String: Any]) ?? [:],
            files: filesRaw
        )
    }

    /// 把 GeneratedApp 写入临时目录，生成 manifest.json + 所有文件。
    /// 返回临时目录 URL，调用方负责后续打包或直接安装。
    static func writeToDisk(_ app: GeneratedApp,
                            completion: @escaping (Result<URL, Error>) -> Void) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai_gen_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            completion(.failure(GenError.writeFailed(error.localizedDescription)))
            return
        }

        // 写 manifest.json（先不含 icon 字段）
        var manifest: [String: Any] = [
            "appId": app.appId,
            "version": app.version,
            "name": app.name,
            "minHostVersion": "1.0.0",
            "pages": app.pages,
            "capabilities": app.capabilities
        ]
        if !app.description.isEmpty {
            manifest["description"] = app.description
        }

        // 写所有文件
        do {
            for (path, content) in app.files {
                let target = tmp.appendingPathComponent(path)
                let parent = target.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                guard let data = content.data(using: .utf8) else {
                    throw GenError.writeFailed("\(path) 编码失败")
                }
                try data.write(to: target)
            }
        } catch let err as GenError {
            completion(.failure(err))
            return
        } catch {
            completion(.failure(GenError.writeFailed(error.localizedDescription)))
            return
        }

        // 渲染 icon.svg → icon.png
        let hasSVG = app.files["icon.svg"] != nil
        let finalize: () -> Void = {
            var m = manifest
            let iconPath = tmp.appendingPathComponent("icon.png")
            if FileManager.default.fileExists(atPath: iconPath.path) {
                m["icon"] = "icon.png"
            }
            if let data = try? JSONSerialization.data(withJSONObject: m,
                                                      options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: tmp.appendingPathComponent("manifest.json"))
            }
            completion(.success(tmp))
        }

        guard hasSVG, let svg = app.files["icon.svg"] else {
            finalize()
            return
        }

        SVGIconRenderer.render(svg: svg, size: 512) { image in
            if let image = image, let png = image.pngData() {
                try? png.write(to: tmp.appendingPathComponent("icon.png"))
            }
            finalize()
        }
    }



}

// MARK: - UIColor Hex
extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
