import Foundation

final class HTTPProvider: CapabilityProvider {
    static var capability: String { "http" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    /// 默认请求超时（秒）
    private static let defaultTimeout: TimeInterval = 30
    /// 响应体大小上限（字节）。10MB，防止恶意小程序把宿主内存打爆。
    private static let maxResponseBytes = 10 * 1024 * 1024

    /// 复用单例会话，避免高频 wx.request（轮询等）反复创建 URLSession。
    /// downloadTask 并发安全；per-request 超时通过 URLRequest.timeoutInterval 覆盖。
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "request" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let urlStr = params["url"] as? String, let url = URL(string: urlStr) else {
            completion(.failure(.invalidParams("url required")))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = params["method"] as? String ?? "GET"
        if let headers = params["headers"] as? [String: String] {
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        }
        if let body = params["body"] as? String { req.httpBody = body.data(using: .utf8) }

        // 允许小程序自定义超时，但收紧上限（防无限挂起）
        let timeout = min(max((params["timeout"] as? TimeInterval) ?? Self.defaultTimeout, 1), 60)
        req.timeoutInterval = timeout

        // 下载到临时文件再校验大小，避免大响应直接攒进内存
        Self.sharedSession.downloadTask(with: req) { tmpURL, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(.providerError(err.localizedDescription)))
                    return
                }
                guard let http = resp as? HTTPURLResponse,
                      let tmp = tmpURL else {
                    completion(.failure(.providerError("无响应")))
                    return
                }

                // 响应体大小上限检查
                let expected = http.expectedContentLength
                if expected > Self.maxResponseBytes {
                    try? FileManager.default.removeItem(at: tmp)
                    completion(.failure(.providerError("响应体过大（超过 \(Self.maxResponseBytes / (1024 * 1024))MB）")))
                    return
                }
                var size: Int64 = 0
                if let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path),
                   let s = attrs[.size] as? Int64 {
                    size = s
                }
                if size > Self.maxResponseBytes {
                    try? FileManager.default.removeItem(at: tmp)
                    completion(.failure(.providerError("响应体过大（超过 \(Self.maxResponseBytes / (1024 * 1024))MB）")))
                    return
                }

                let data = (try? Data(contentsOf: tmp)) ?? Data()
                try? FileManager.default.removeItem(at: tmp)
                let status = http.statusCode
                let text = String(data: data, encoding: .utf8) ?? ""
                completion(.success(["status": status, "body": text]))
            }
        }.resume()
    }
}
