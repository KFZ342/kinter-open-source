import Foundation

/// 发布编排器：把已安装应用上传到 Kinter 服务器。
/// 服务器接收 ZIP，存盘，返回该用户的商店源地址。
final class StorePublisher {
    static let shared = StorePublisher()
    private init() {}

    enum PublishError: LocalizedError {
        case noLogin
        case missingEntry
        case zipFailed
        case uploadFailed(String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .noLogin:              return "请先在设置 → 账号里登录"
            case .missingEntry:         return "应用缺少 index.html"
            case .zipFailed:            return "打包失败"
            case .uploadFailed(let s):  return "上传失败: \(s)"
            case .parseFailed(let s):   return "响应解析失败: \(s)"
            }
        }
    }

    struct PublishResult {
        let appId: String
        let name: String
        let version: String
        let sourceURL: String
        /// 发布时声明的售价（元）。0 = 免费
        let price: Double
    }

    // MARK: - 发布

    func publish(app: InstalledApp,
                 price: Double = 0,
                 completion: @escaping (Result<PublishResult, Error>) -> Void) {
        guard let token = AuthStore.shared.accessToken,
              let user = KinterAuthManager.shared.restoreSession() else {
            completion(.failure(PublishError.noLogin))
            return
        }
        _ = user

        // 1. 读文件
        let entries: [ZipWriter.Entry]
        do {
            entries = try readAppFiles(app)
        } catch {
            completion(.failure(error))
            return
        }
        guard entries.contains(where: { $0.path == "index.html" }) else {
            completion(.failure(PublishError.missingEntry))
            return
        }

        // 2. 打 ZIP
        let zipData = ZipWriter.build(entries: entries)
        NSLog("[Publish] zip built, %d bytes, %d files", zipData.count, entries.count)

        // 3. 构造 multipart（附带价格字段，服务端写进商店索引）
        let boundary = "----KinterBoundary\(UUID().uuidString)"
        let body = buildMultipart(
            boundary: boundary,
            filename: "\(app.appId).zip",
            data: zipData,
            price: price
        )

        // 4. 发请求
        guard let base = publishBaseURL() else {
            completion(.failure(PublishError.uploadFailed("服务器地址无效")))
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("/api/apps/publish"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 60
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(PublishError.uploadFailed(err.localizedDescription)))
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let data = data ?? Data()
                NSLog("[Publish] HTTP %d, response %d bytes", code, data.count)

                if (200...299).contains(code) {
                    do {
                        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                        let appId = obj["appId"] as? String ?? app.appId
                        let name = obj["name"] as? String ?? app.name
                        let version = obj["version"] as? String ?? app.version
                        let source = obj["sourceURL"] as? String ?? ""
                        let price = (obj["price"] as? Double) ?? price
                        completion(.success(PublishResult(
                            appId: appId, name: name, version: version,
                            sourceURL: source, price: price
                        )))
                    } catch {
                        completion(.failure(PublishError.parseFailed(error.localizedDescription)))
                    }
                    return
                }

                // 错误分支
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errCode = obj["error"] as? String {
                    completion(.failure(PublishError.uploadFailed(errCode)))
                } else {
                    completion(.failure(PublishError.uploadFailed("HTTP \(code)")))
                }
            }
        }.resume()
    }

    // MARK: - 服务器地址

    private func publishBaseURL() -> URL? {
        let raw = AppSettings.shared.authServerURL ?? KinterAuthManager.defaultServerURL
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed)
    }

    // MARK: - multipart

    private func buildMultipart(boundary: String, filename: String, data: Data, price: Double) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        // 价格字段（元，0 = 免费）
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"price\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(price)".data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - 读文件

    private func readAppFiles(_ app: InstalledApp) throws -> [ZipWriter.Entry] {
        let dir = app.directory
        var entries: [ZipWriter.Entry] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw PublishError.zipFailed
        }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let rel = url.path.replacingOccurrences(of: dir.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !rel.isEmpty else { continue }
            if rel == "icon.png" { continue }
            if let data = try? Data(contentsOf: url) {
                entries.append(ZipWriter.Entry(path: rel, data: data))
            }
        }
        return entries
    }
}
