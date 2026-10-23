import Foundation

/// 文件能力：读写当前小程序自己的数据目录。
/// 目录位于 Documents/Data/{appId}/，可在 Files app 中浏览。
final class FilesProvider: CapabilityProvider, AppContextInjectable {
    static var capability: String { "files" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    /// 由 CapabilityGateway 在调用前注入当前 appId
    var appId: String?

    private var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let appId = appId ?? "_unknown"
        let url = base.appendingPathComponent("Data", isDirectory: true)
                      .appendingPathComponent(appId, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 把相对路径解析为目录内的绝对 URL，拒绝越界。
    private func resolve(_ name: String) -> URL? {
        if name.contains("..") { return nil }
        if name.hasPrefix("/") { return nil }
        let url = dir.appendingPathComponent(name)
        let base = dir.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target == base || target.hasPrefix(base + "/") else { return nil }
        return url
    }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        // ---- 不需要 name 的方法 ----

        if method == "info" {
            completion(.success(["path": dir.path,
                                 "exists": FileManager.default.fileExists(atPath: dir.path)]))
            return
        }

        if method == "list" || method == "listDir" {
            // 可选 name：不传表示根目录，传了就列子目录
            let name = params["name"] as? String ?? ""
            let target: URL
            if name.isEmpty {
                target = dir
            } else {
                guard let url = resolve(name) else {
                    completion(.failure(.invalidParams("非法路径")))
                    return
                }
                target = url
            }
            let items = (try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? []
            completion(.success(["files": items.sorted(),
                                 "path": target.path]))
            return
        }

        // ---- 需要 name 的方法 ----

        guard let name = params["name"] as? String, !name.isEmpty else {
            completion(.failure(.invalidParams("name required")))
            return
        }
        guard let url = resolve(name) else {
            completion(.failure(.invalidParams("非法路径")))
            return
        }

        switch method {
        case "write":
            let text = params["data"] as? String ?? ""
            do {
                // 父目录不存在则创建
                let parent = url.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parent.path) {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try text.write(to: url, atomically: true, encoding: .utf8)
                completion(.success(["path": url.path, "size": text.utf8.count]))
            } catch {
                completion(.failure(.providerError(error.localizedDescription)))
            }

        case "read":
            guard let t = try? String(contentsOf: url, encoding: .utf8) else {
                completion(.failure(.providerError("文件不存在或无法读取")))
                return
            }
            completion(.success(["data": t, "path": url.path]))

        case "remove":
            do {
                try FileManager.default.removeItem(at: url)
                completion(.success(["ok": true]))
            } catch {
                completion(.failure(.providerError(error.localizedDescription)))
            }

        case "mkdir":
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                completion(.success(["ok": true, "path": url.path]))
            } catch {
                completion(.failure(.providerError(error.localizedDescription)))
            }

        case "exists":
            completion(.success(["exists": FileManager.default.fileExists(atPath: url.path)]))

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
}
