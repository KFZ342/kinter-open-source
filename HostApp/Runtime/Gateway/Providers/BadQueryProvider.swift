import Foundation

/// 基于 bad_query 的沙盒扩展能力（L3）。
///
/// 设计原则：不预判系统版本，一律"先探测再使用"。
/// - 每次操作先调 bad_query 拿 sandbox extension 句柄。
/// - 句柄 > 0：内核已放行，用标准 FileManager 操作该路径，结束后立即 release。
/// - 句柄 <= 0：不猜测原因，把原始错误码透传给调用方，并标记 degraded。
///   AI 拿到 degraded=true 后应改用沙盒内路径（wx.files / wx.writeFile）。
///
/// 安全护栏：内置危险路径黑名单，即使越权成功也拒绝触碰系统关键数据。
final class BadQueryProvider: CapabilityProvider {
    static var capability: String { "badQuery" }
    static var level: CapabilityLevel { .l3 }

    init() {}

    /// 串行队列：bad_query 的 dlsym 全局符号与 containermanagerd 查询非线程安全，
    /// 所有 C 调用与文件操作必须在同一队列串行执行，避免并发时句柄/查询串扰。
    private let serial = DispatchQueue(label: "com.kinter.badquery.serial")

    /// 读取上限（32MB）：防止把超大文件整个读进内存
    private static let maxReadBytes = 32 * 1024 * 1024
    /// 写入上限（64MB）
    private static let maxWriteBytes = 64 * 1024 * 1024

    // MARK: - 安全护栏

    /// 危险路径前缀。写入/删除操作命中即拒，读取操作仅对最敏感目录设防。
    /// 目的不是阻止一切，而是防止 AI 被诱导误删系统文件或窃取凭据。
    private static let denyWritePrefixes: [String] = [
        "/System/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/private/var/db/",
        "/private/var/Keychains/",
        "/private/etc/",
        "/private/preboot/",
        "/var/db/",
        "/var/Keychains/",
        "/var/jb/"
    ]

    private static let denyReadPrefixes: [String] = [
        "/private/var/Keychains/",
        "/var/Keychains/"
    ]

    private static func isDenied(_ path: String, forWrite: Bool) -> String? {
        // iOS 上 /var 是 /private/var 的符号链接：先归一化，杜绝用 /var 写法绕过 /private/ 黑名单
        let normalized = path.hasPrefix("/var/") ? "/private" + path : path
        if forWrite {
            for p in denyWritePrefixes where normalized.hasPrefix(p) {
                return "拒绝写入系统保护区：\(p)"
            }
        }
        for p in denyReadPrefixes where normalized.hasPrefix(p) {
            return "拒绝读取凭据存储区：\(p)"
        }
        return nil
    }

    // MARK: - 错误码语义（来自 bad_query.c）
    private static func describe(_ code: Int64) -> String {
        switch code {
        case -1:   return "函数解析失败（当前系统可能不存在 containermanager 符号）"
        case -2:   return "创建 container query 失败"
        case -3:   return "目标超出 containermanager 可查询范围"
        case -4:   return "内核拒绝发放 sandbox extension"
        case -5:   return "路径拼接失败"
        case -254: return "目标文件不存在"
        case -255: return "路径不是绝对路径"
        default:   return "未知错误码 \(code)"
        }
    }

    /// 根据错误码给出后续可达路径的建议。帮助 AI 在一次失败后换对方向。
    private static func hint(for code: Int64) -> String {
        switch code {
        case -1:
            return "当前系统无 containermanager 符号，越权不可用。请改用 wx.writeFile / wx.readFile。"
        case -3:
            return "该路径超出 containermanager 可查询范围。可尝试改读以下可达区域：/var/containers/Shared/SystemGroup/、/var/mobile/Containers/Data/Application/、/var/mobile/Containers/Data/InternalDaemon/、/var/mobile/Containers/Data/PluginKitPlugin/、/var/mobile/Containers/Shared/AppGroup/。"
        case -4:
            return "内核拒绝发放扩展。可能是系统已修复或路径未被 any container 引用。换一个已知被 App 使用的路径重试，或改用沙盒内 API。"
        case -254:
            return "目标不存在。可用 badQuery.listDir 枚举父目录确认实际路径。"
        case -255:
            return "路径必须是以 / 开头的绝对路径。"
        default:
            return "该路径无法获得沙盒扩展。可改用 wx.writeFile / wx.readFile，或换一个路径重试。"
        }
    }

    /// 尝试消费目标路径的沙盒扩展。
    /// - Returns: (handle, errorCode)。handle > 0 表示成功。
    private static func consume(path: String, create: Bool) -> (Int64, Int64) {
        var cPath = path.utf8CString.map { Int8($0) }
        let h = bad_query(&cPath, create, nil, false)
        return (h, h)
    }

    // MARK: - 入口

    func invoke(method: String, params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void) {
        // 全部操作串行执行（C 层非线程安全）；completion 保持调用线程，
        // 上层如需 UI 更新自行切主线程
        serial.async { [self] in
            self._invoke(method: method, params: params, completion: completion)
        }
    }

    private func _invoke(method: String, params: [String: Any],
                         completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "probe":
            probe(params: params, completion: completion)

        case "readFile":
            withExtension(method: method, params: params, forWrite: false, completion: completion) { path, params in
                let attrs = try FileManager.default.attributesOfItem(atPath: path)
                let size = (attrs[.size] as? Int) ?? 0
                guard size <= Self.maxReadBytes else {
                    throw ProviderFailure.invalidParams("文件过大（\(size) 字节，上限 \(Self.maxReadBytes)）。请改用 shell/流式方式读取。")
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let asText = (params["asText"] as? Bool) ?? false
                var out: [String: Any] = ["path": path, "size": data.count]
                if asText {
                    if let s = String(data: data, encoding: .utf8) {
                        out["text"] = s
                    } else {
                        out["data"] = data.base64EncodedString()
                        out["textDecoded"] = false
                        out["note"] = "内容不是有效 UTF-8，已按 base64 返回"
                    }
                } else {
                    out["data"] = data.base64EncodedString()
                }
                return out
            }

        case "writeFile":
            withExtension(method: method, params: params, forWrite: true, completion: completion) { path, params in
                let data: Data
                if let base64 = params["data"] as? String, let d = Data(base64Encoded: base64) {
                    data = d
                } else if let text = params["text"] as? String {
                    data = Data(text.utf8)
                } else {
                    throw ProviderFailure.invalidParams("需要 data(base64) 或 text")
                }
                guard data.count <= Self.maxWriteBytes else {
                    throw ProviderFailure.invalidParams("写入内容过大（\(data.count) 字节，上限 \(Self.maxWriteBytes)）")
                }
                let create = (params["create"] as? Bool) ?? true
                let url = URL(fileURLWithPath: path)
                if create {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true)
                }
                try data.write(to: url)
                return ["path": path, "size": data.count, "ok": true]
            }

        case "stat":
            withExtension(method: method, params: params, forWrite: false, completion: completion) { path, _ in
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                var size = 0
                var modified: String?
                if exists {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                        size = (attrs[.size] as? Int) ?? 0
                        if let d = attrs[.modificationDate] as? Date {
                            modified = ISO8601DateFormatter().string(from: d)
                        }
                    }
                }
                var out: [String: Any] = ["path": path, "exists": exists,
                                          "isDirectory": isDir.boolValue, "size": size]
                if let m = modified { out["modified"] = m }
                return out
            }

        case "listDir":
            withExtension(method: method, params: params, forWrite: false, completion: completion) { path, params in
                let maxInode = Self.clampInt64(params["maxInode"], fallback: 200_000, lower: 1, upper: 500_000)
                var cPath = path.utf8CString.map { Int8($0) }
                guard let raw = bad_query_list(&cPath, maxInode) else {
                    throw ProviderFailure.runtime("目录枚举失败（bad_query_list 返回空）")
                }
                defer { free(raw) }
                var files = String(cString: raw).split(separator: "\n").map(String.init)
                let limit = Self.clampInt(params["limit"], fallback: 500, lower: 1, upper: 20_000)
                let truncated = files.count > limit
                if truncated { files = Array(files.prefix(limit)) }
                var out: [String: Any] = ["path": path, "files": files, "count": files.count]
                if truncated { out["truncated"] = true }
                return out
            }

        case "listTree":
            withExtension(method: method, params: params, forWrite: false, completion: completion) { path, params in
                let maxInode = Self.clampInt64(params["maxInode"], fallback: 200_000, lower: 1, upper: 500_000)
                let maxDepth = Self.clampInt(params["maxDepth"], fallback: 3, lower: 1, upper: 10)
                let limit = Self.clampInt(params["limit"], fallback: 1000, lower: 1, upper: 50_000)
                let entries = try Self.walkTree(root: path, maxInode: maxInode,
                                                maxDepth: maxDepth, limit: limit)
                return ["path": path, "entries": entries,
                        "count": entries.count,
                        "truncated": entries.count >= limit]
            }

        case "remove":
            withExtension(method: method, params: params, forWrite: true, completion: completion) { path, _ in
                try FileManager.default.removeItem(atPath: path)
                return ["path": path, "ok": true]
            }

        case "mkdir":
            withExtension(method: method, params: params, forWrite: true, completion: completion) { path, _ in
                try FileManager.default.createDirectory(atPath: path,
                                                        withIntermediateDirectories: true)
                return ["path": path, "ok": true]
            }

        case "copy":
            let src = params["from"] as? String ?? ""
            let dst = params["to"] as? String ?? ""
            guard !src.isEmpty, !dst.isEmpty else {
                return completion(.failure(.invalidParams("from / to 必填")))
            }
            if let deny = Self.isDenied(dst, forWrite: true) {
                return completion(.success(["ok": false, "degraded": false,
                                            "reason": deny, "path": dst]))
            }
            // 源和目标都需要扩展，分别拿
            let (hSrc, cSrc) = Self.consume(path: src, create: false)
            guard hSrc > 0 else {
                return completion(.success(["ok": false, "degraded": true, "path": src,
                                            "code": cSrc, "reason": Self.describe(cSrc),
                                            "hint": Self.hint(for: cSrc)]))
            }
            defer { bad_query_release(hSrc) }
            let (hDst, cDst) = Self.consume(path: dst, create: true)
            guard hDst > 0 else {
                return completion(.success(["ok": false, "degraded": true, "path": dst,
                                            "code": cDst, "reason": Self.describe(cDst),
                                            "hint": Self.hint(for: cDst)]))
            }
            defer { bad_query_release(hDst) }
            do {
                try? FileManager.default.createDirectory(
                    atPath: (dst as NSString).deletingLastPathComponent,
                    withIntermediateDirectories: true)
                try FileManager.default.copyItem(atPath: src, toPath: dst)
                completion(.success(["ok": true, "from": src, "to": dst, "degraded": false]))
            } catch {
                completion(.failure(.providerError(error.localizedDescription)))
            }

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    // MARK: - 递归遍历

    /// 递归枚举目录。每层都重新拿一次沙盒扩展（子目录可能需要独立扩展）。
    private static func walkTree(root: String, maxInode: Int64,
                                 maxDepth: Int, limit: Int) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var queue: [(String, Int)] = [(root, 0)]
        var cursor = 0 // 索引遍历，避免 removeFirst 的 O(n²)

        while cursor < queue.count {
            let (current, depth) = queue[cursor]
            cursor += 1
            if out.count >= limit { break }

            let (handle, _) = consume(path: current, create: false)
            guard handle > 0 else { continue }

            let items: [String]
            do {
                var cPath = current.utf8CString.map { Int8($0) }
                if let raw = bad_query_list(&cPath, maxInode) {
                    defer { free(raw) }
                    items = String(cString: raw).split(separator: "\n").map(String.init)
                } else {
                    items = []
                }
            }
            bad_query_release(handle)

            for item in items {
                if out.count >= limit { break }
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: item, isDirectory: &isDir)
                out.append(["path": item,
                            "depth": depth + 1,
                            "isDirectory": isDir.boolValue,
                            "exists": exists])
                if isDir.boolValue && depth + 1 < maxDepth {
                    queue.append((item, depth + 1))
                }
            }
        }
        return out
    }

    // MARK: - 参数钳制

    private static func clampInt(_ v: Any?, fallback: Int, lower: Int, upper: Int) -> Int {
        guard let n = v as? NSNumber else { return fallback }
        return Swift.min(Swift.max(n.intValue, lower), upper)
    }

    private static func clampInt64(_ v: Any?, fallback: Int64, lower: Int64, upper: Int64) -> Int64 {
        guard let n = v as? NSNumber else { return fallback }
        return Swift.min(Swift.max(n.int64Value, lower), upper)
    }

    // MARK: - 探测

    /// 探测漏洞在当前设备上是否可用。不抛错，永远返回结构化结果。
    private func probe(params: [String: Any],
                       completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let probePath = (params["path"] as? String)
            ?? "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

        let (handle, code) = Self.consume(path: probePath, create: false)
        if handle > 0 {
            bad_query_release(handle)
            completion(.success([
                "available": true,
                "probePath": probePath,
                "code": 0,
                "reason": "沙盒扩展获取成功",
                "degraded": false
            ]))
        } else {
            completion(.success([
                "available": false,
                "probePath": probePath,
                "code": code,
                "reason": Self.describe(code),
                "degraded": true,
                "hint": Self.hint(for: code)
            ]))
        }
    }

    // MARK: - 带探测的执行

    private enum ProviderFailure: Error {
        case invalidParams(String)
        case runtime(String)
    }

    private func withExtension(method: String,
                               params: [String: Any],
                               forWrite: Bool,
                               completion: @escaping (Result<Any, GatewayError>) -> Void,
                               body: @escaping (String, [String: Any]) throws -> [String: Any]) {
        guard let path = params["path"] as? String, !path.isEmpty else {
            return completion(.failure(.invalidParams("path 必填")))
        }
        guard path.hasPrefix("/") else {
            return completion(.failure(.invalidParams("path 必须是绝对路径")))
        }

        if let deny = Self.isDenied(path, forWrite: forWrite) {
            return completion(.success([
                "ok": false,
                "degraded": false,
                "blocked": true,
                "method": method,
                "path": path,
                "reason": deny,
                "hint": "这是被安全护栏拦截的系统保护区，不会执行。请换一个非系统路径。"
            ]))
        }

        let create = (params["create"] as? Bool) ?? forWrite
        let (handle, code) = Self.consume(path: path, create: create)

        guard handle > 0 else {
            return completion(.success([
                "ok": false,
                "degraded": true,
                "method": method,
                "path": path,
                "code": code,
                "reason": Self.describe(code),
                "hint": Self.hint(for: code)
            ]))
        }

        defer { bad_query_release(handle) }

        do {
            let result = try body(path, params)
            var out = result
            out["degraded"] = false
            completion(.success(out))
        } catch let e as ProviderFailure {
            switch e {
            case .invalidParams(let m): completion(.failure(.invalidParams(m)))
            case .runtime(let m):       completion(.failure(.providerError(m)))
            }
        } catch {
            completion(.failure(.providerError(error.localizedDescription)))
        }
    }
}
