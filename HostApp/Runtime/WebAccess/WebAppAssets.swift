import Foundation
import UIKit

/// Web 端的小程序资源层：解析页面、注入 SDK、按 MIME 输出静态资源。
/// 页面渲染与原生保持一致：.ktml 走同一个 KTMLCompiler，.html 原样输出。
enum WebAppAssets {

    // MARK: - 路径安全

    /// 应用目录的真实路径（standardize + 解析符号链接后）。
    private static func realRoot(of app: InstalledApp) -> String {
        app.directory.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// 校验并解析应用目录下的相对路径。
    /// 流程：百分号解码一次 → 拒绝绝对路径 / NUL / `..` 段 / 空段 →
    /// standardize → 解析符号链接 → 根目录前缀包含二次校验。
    /// 返回 nil 表示路径越界或非法。
    private static func safeURL(app: InstalledApp, relative raw: String) -> URL? {
        var rel = raw
        if rel.hasPrefix("/") { rel.removeFirst() }
        let decoded = rel.removingPercentEncoding ?? rel
        guard !decoded.isEmpty, !decoded.contains("\0") else { return nil }
        guard !decoded.hasPrefix("file://") else { return nil }

        let segments = decoded.components(separatedBy: "/")
        for seg in segments {
            if seg == ".." { return nil }
            if seg == "" && seg != segments.last { return nil }
        }

        let root = app.directory.standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appendingPathComponent(decoded)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = root.path
        let targetPath = target.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { return nil }
        return target
    }

    /// 解析页面路径（与 PageRouter 规则一致：先找 .html 再找 .ktml，自动补后缀，防穿越）。
    static func resolvePage(app: InstalledApp, path rawPath: String) throws -> URL {
        var filePath = rawPath
        if let q = filePath.firstIndex(of: "?") { filePath = String(filePath[..<q]) }
        guard !filePath.isEmpty else { return try resolvePage(app: app, path: "index") }

        var target: URL
        if filePath.hasSuffix(".html") || filePath.hasSuffix(".ktml") {
            guard let url = safeURL(app: app, relative: filePath) else {
                throw PageError.notFound(rawPath)
            }
            target = url
        } else {
            guard let base = safeURL(app: app, relative: filePath) else {
                throw PageError.notFound(rawPath)
            }
            let htmlURL = base.appendingPathExtension("html")
            let ktmlURL = base.appendingPathExtension("ktml")
            if FileManager.default.fileExists(atPath: htmlURL.path) {
                target = htmlURL
            } else if FileManager.default.fileExists(atPath: ktmlURL.path) {
                target = ktmlURL
            } else {
                target = htmlURL
            }
        }

        // 解析真实路径后二次校验（符号链接兜底）
        let resolved = target.standardizedFileURL.resolvingSymlinksInPath().path
        let root = realRoot(of: app)
        guard resolved == root || resolved.hasPrefix(root + "/") else { throw PageError.notFound(rawPath) }
        guard FileManager.default.fileExists(atPath: resolved) else { throw PageError.notFound(rawPath) }
        return target
    }

    enum PageError: LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let p): return "页面不存在：\(p)"
            }
        }
    }

    /// 渲染页面文档，并把「Web 桥接 + wx SDK + KTML 运行时」注入到 head 里。
    /// 原生是靠 WKUserContentController 在 documentStart 注入；浏览器没有这个能力，
    /// 所以这里改成把脚本塞进页面文档，执行时机等价（都在页面脚本之前）。
    static func renderDocument(app: InstalledApp, path: String) throws -> String {
        let url = try resolvePage(app: app, path: path)
        let source: String
        if url.pathExtension.lowercased() == "ktml" {
            let raw = try String(contentsOf: url, encoding: .utf8)
            source = try KTMLCompiler.shared.compile(source: raw, baseURL: app.directory)
        } else {
            guard let s = try? String(contentsOf: url, encoding: .utf8) else {
                throw PageError.notFound(path)
            }
            source = s
        }
        return injectSDK(into: source, appId: app.appId)
    }

    private static func injectSDK(into document: String, appId: String) -> String {
        let injection = """
        <script>window.__KINTER_WEB_APP_ID__ = "\(jsEscape(appId))";</script>
        <script src="/web-bridge-v2.js"></script>
        <script src="/sdk/wx.js"></script>
        <script src="/sdk/ktml.js"></script>
        """
        // 优先插到 <head ...> 之后；没有 head 就插到 <html ...> 之后；再不行直接前置
        if let headRange = rangeOfOpeningTag(named: "head", in: document) {
            // 注意要保留 <head> 标签本身，只在其后插入
            return document.replacingCharacters(in: headRange,
                                                with: String(document[headRange]) + "\n" + injection)
        }
        // 有些页面没写 <head>，这时插到 <meta charset> 之后，别让脚本排在字符集声明前面
        if let charsetRange = rangeOfOpeningTag(named: "meta charset", in: document) {
            return document.replacingCharacters(in: charsetRange, with: String(document[charsetRange]) + "\n" + injection)
        }
        if let htmlRange = rangeOfOpeningTag(named: "html", in: document) {
            let tag = String(document[htmlRange])
            return document.replacingCharacters(in: htmlRange, with: tag + "\n" + injection)
        }
        return injection + "\n" + document
    }

    /// 返回 "<head ...>" 在文档中的范围（含尖括号）。
    private static func rangeOfOpeningTag(named name: String, in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: "<" + name, options: .caseInsensitive) else { return nil }
        guard let end = text[start.lowerBound...].firstIndex(of: ">") else { return nil }
        return start.lowerBound..<text.index(after: end)
    }

    private static func jsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - 静态资源

    private static let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "htm": "text/html; charset=utf-8",
        "js": "application/javascript; charset=utf-8",
        "mjs": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "txt": "text/plain; charset=utf-8",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "mp3": "audio/mpeg",
        "wav": "audio/wav",
        "m4a": "audio/mp4",
        "mp4": "video/mp4",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "wasm": "application/wasm"
    ]

    static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return mimeTypes[ext] ?? "application/octet-stream"
    }

    /// 应用目录下的任意文件。
    static func assetResponse(app: InstalledApp, relativePath: String) -> HTTPResponse {
        guard let file = safeURL(app: app, relative: relativePath) else {
            return .failure(403, code: "forbidden", message: "非法路径")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir),
              !isDir.boolValue else {
            return .failure(404, code: "not_found", message: "资源不存在：\(relativePath)")
        }
        guard let data = try? Data(contentsOf: file) else {
            return .failure(404, code: "not_found", message: "资源不存在：\(relativePath)")
        }
        return HTTPResponse(status: 200,
                            headers: ["Content-Type": mimeType(for: relativePath),
                                      "Cache-Control": "public, max-age=300"],
                            body: data)
    }

    /// 应用图标（优先用户自定义图标，其次 manifest.icon，最后生成占位）。
    static func iconResponse(app: InstalledApp) -> HTTPResponse {
        if let name = app.iconFileName,
           let url = safeURL(app: app, relative: name) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
               !isDir.boolValue,
               let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200,
                                    headers: ["Content-Type": mimeType(for: name),
                                              "Cache-Control": "public, max-age=86400"],
                                    body: data)
            }
        }
        if let iconData = try? Data(contentsOf: app.manifestURL),
           let m = try? ManifestParser.parse(data: iconData),
           let icon = m.icon,
           let url = safeURL(app: app, relative: icon),
           let data = try? Data(contentsOf: url) {
            return HTTPResponse(status: 200,
                                headers: ["Content-Type": mimeType(for: icon),
                                          "Cache-Control": "public, max-age=86400"],
                                body: data)
        }
        // 占位图：用名字首字生成一个圆角方块（与原生默认图标的观感一致）
        let image = placeholderIcon(text: String(app.name.prefix(1)), seed: app.appId)
        return HTTPResponse(status: 200,
                            headers: ["Content-Type": "image/png",
                                      "Cache-Control": "public, max-age=86400"],
                            body: image)
    }

    private static func placeholderIcon(text: String, seed: String) -> Data {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // 用 appId 派生色相，同一个应用每次都是同一个配色，不同应用能区分开
            var hash: UInt64 = 1469598103934665603
            for ch in seed.utf8 { hash = (hash ^ UInt64(ch)) &* 1099511628211 }
            let hue = CGFloat(hash % 360) / 360.0
            let top = UIColor(hue: hue, saturation: 0.62, brightness: 0.96, alpha: 1).cgColor
            let bottom = UIColor(hue: fmod(hue + 0.08, 1.0), saturation: 0.72, brightness: 0.78, alpha: 1).cgColor
            let colors = [top, bottom] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient,
                                                 start: .zero,
                                                 end: CGPoint(x: size.width, y: size.height),
                                                 options: [])
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 54, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let s = NSAttributedString(string: text, attributes: attrs)
            let sSize = s.size()
            s.draw(at: CGPoint(x: (size.width - sSize.width) / 2,
                               y: (size.height - sSize.height) / 2))
        }
        return image.pngData() ?? Data()
    }

    // MARK: - SDK 资源

    /// 把 SDK 目录里的 wx.js / ktml.js 读出来，供 Web 页面作为脚本加载。
    static func sdkScript(named name: String) -> String? {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "SDK"),
            Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "web"),
            Bundle.main.url(forResource: name, withExtension: "js")
        ].compactMap { $0 }
        for url in candidates {
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return nil
    }
}
