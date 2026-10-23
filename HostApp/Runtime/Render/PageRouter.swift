import UIKit
import WebKit
import JavaScriptCore

/// 小程序页面栈。
/// 原生维护页面历史，每次导航让 WebView 加载对应 HTML 文件。
/// 页面路径对应 manifest 的 pages 数组，如 "pages/detail/detail" -> pages/detail/detail.html。
final class PageRouter {

    /// 栈深上限（与微信一致）
    static let maxDepth = 10

    private(set) var stack: [String] = []
    private var rootDir: URL!
    private weak var webView: WKWebView?

    enum RouterError: LocalizedError {
        case notConfigured
        case pageNotFound(String)
        case stackFull
        case cannotGoBack

        var errorDescription: String? {
            switch self {
            case .notConfigured:        return "页面路由未初始化"
            case .pageNotFound(let p):  return "页面不存在：\(p)"
            case .stackFull:            return "页面栈已满（最多 \(PageRouter.maxDepth) 层）"
            case .cannotGoBack:         return "已经在首页，无法返回"
            }
        }
    }

    // MARK: - 初始化

    /// 绑定 WebView 与小程序根目录，并加载入口页。
    func configure(webView: WKWebView, rootDir: URL, entry: String) throws {
        self.webView = webView
        self.rootDir = rootDir
        stack = []
        try push(path: entry, animated: false)
    }

    // MARK: - 导航 API

    /// 保留当前页，打开新页。
    func navigateTo(_ path: String) throws {
        guard stack.count < Self.maxDepth else { throw RouterError.stackFull }
        try push(path: path, animated: true, direction: .forward)
    }

    /// 替换当前页，不能返回。
    func redirectTo(_ path: String) throws {
        let url = try resolve(path)
        _ = stack.popLast()
        try load(url: url, path: path, animated: true, direction: .forward)
        stack.append(path)
    }

    /// 关闭所有页面，只保留目标页。
    func reLaunch(_ path: String) throws {
        let url = try resolve(path)
        stack = []
        try load(url: url, path: path, animated: true, direction: .forward)
        stack.append(path)
    }

    /// 返回上一页或多页。
    func navigateBack(delta: Int = 1) throws {
        guard stack.count > 1 else { throw RouterError.cannotGoBack }
        let step = min(max(delta, 1), stack.count - 1)
        stack.removeLast(step)
        guard let target = stack.last else { throw RouterError.cannotGoBack }
        let url = try resolve(target)
        try load(url: url, path: target, animated: true, direction: .backward)
    }

    // MARK: - 内部

    private enum Direction { case forward, backward }

    private func push(path: String, animated: Bool, direction: Direction = .forward) throws {
        let url = try resolve(path)
        try load(url: url, path: path, animated: animated, direction: direction)
        stack.append(path)
    }

    private func load(url: URL, path: String, animated: Bool, direction: Direction) throws {
        guard let webView = webView else { throw RouterError.notConfigured }

        // .ktml 页面先编译成 HTML 再加载
        if url.pathExtension.lowercased() == "ktml" {
            do {
                let source = try String(contentsOf: url, encoding: .utf8)
                let html = try KTMLCompiler.shared.compile(source: source, baseURL: rootDir)
                webView.loadHTMLString(html, baseURL: rootDir)
            } catch let err as KTMLCompiler.CompileError {
                throw RouterError.pageNotFound("\(path): \(err.localizedDescription)")
            }
            return
        }

        webView.loadFileURL(url, allowingReadAccessTo: rootDir)
    }

    /// 把页面路径解析成绝对 URL，并做安全检查。
    /// 支持 `pages/detail/detail?title=x&idx=1` 形式：
    /// 文件部分用于定位与存在性校验，查询串原样附加到最终 URL 上。
    private func resolve(_ path: String) throws -> URL {
        guard let rootDir = rootDir else { throw RouterError.notConfigured }

        // 拆分 query / fragment
        var filePath = path
        var query: String? = nil
        if let qIdx = filePath.firstIndex(of: "?") {
            query = String(filePath[filePath.index(after: qIdx)...])
            filePath = String(filePath[..<qIdx])
        }
        var fileURL: URL
        var target: String
        let root = rootDir.standardizedFileURL.path

        // 先找 .html，再找 .ktml
        if filePath.hasSuffix(".html") || filePath.hasSuffix(".ktml") {
            fileURL = rootDir.appendingPathComponent(filePath)
            target = fileURL.standardizedFileURL.path
        } else {
            let htmlURL = rootDir.appendingPathComponent(filePath + ".html")
            let ktmlURL = rootDir.appendingPathComponent(filePath + ".ktml")
            let hasHTML = FileManager.default.fileExists(atPath: htmlURL.path)
            let hasKTML = FileManager.default.fileExists(atPath: ktmlURL.path)
            NSLog("[Router] resolve path=%@ html=%@(%d) ktml=%@(%d)",
                  filePath, htmlURL.path, hasHTML ? 1 : 0, ktmlURL.path, hasKTML ? 1 : 0)
            if hasHTML {
                fileURL = htmlURL
            } else if hasKTML {
                fileURL = ktmlURL
            } else {
                fileURL = htmlURL
            }
            target = fileURL.standardizedFileURL.path
        }

        // 防目录穿越
        guard target.hasPrefix(root + "/") else { throw RouterError.pageNotFound(path) }
        guard FileManager.default.fileExists(atPath: target) else {
            throw RouterError.pageNotFound(path)
        }

        // 附加 query
        guard let q = query else { return fileURL }
        var comps = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
        comps?.query = q
        return comps?.url ?? fileURL
    }
}
