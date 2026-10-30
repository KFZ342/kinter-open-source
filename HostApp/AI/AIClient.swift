import Foundation

/// 与 OpenAI 兼容接口通信。支持流式与非流式。
/// 流式通过 SSE 解析，逐块回调增量文本。
final class AIClient: NSObject {

    struct Message: Codable {
        let role: String
        let content: String
        /// 可选图像：base64 data URL（如 data:image/png;base64,xxx）。有值时按 OpenAI 多模态 content 数组发送
        var imageBase64: String?

        init(role: String, content: String, imageBase64: String? = nil) {
            self.role = role
            self.content = content
            self.imageBase64 = imageBase64
        }
    }

    enum AIError: LocalizedError {
        case notConfigured
        case badURL
        case httpError(Int, String)
        case emptyResponse
        case parseFailed(String)
        case cancelled
        case timeout

        var errorDescription: String? {
            switch self {
            case .notConfigured:        return "请先在设置中配置模型"
            case .badURL:               return "接口地址无效"
            case .httpError(let c, let m): return "请求失败 (\(c)): \(m)"
            case .emptyResponse:        return "模型返回为空"
            case .parseFailed(let s):   return "响应解析失败: \(s)"
            case .cancelled:            return "已取消"
            case .timeout:              return "生成超时（90 秒无响应），已中断，可重试"
            }
        }
    }

    private var session: URLSession?
    private var task: URLSessionDataTask?

    // 流式状态
    private var onDelta: ((String) -> Void)?
    private var onReasoning: ((String) -> Void)?
    private var onComplete: ((Result<String, Error>) -> Void)?
    private var accumulated = ""
    private var reasoning = ""
    private var buffer = ""
    private var httpStatusCode = 0
    private var errorBody = Data()
    private var isSSE = true
    private var rawStreamBody = Data()
    /// 空闲超时保护：流式期间连续 idleTimeout 秒无任何数据则主动中断，避免永久卡住
    private let idleTimeout: TimeInterval = 90
    private var lastDataTime: TimeInterval = 0
    private var idleTimer: Timer?
    /// 是否由空闲超时强制中断（区分用户取消）
    private var timeoutForced = false

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        onDelta = nil
        // 先置空回调，防止 completion 内部再次调用 cancel 导致无限递归
        let complete = onComplete
        onComplete = nil
        complete?(.failure(AIError.cancelled))
    }

    // MARK: - 非流式（保留）

    func chat(messages: [Message],
              completion: @escaping (Result<String, Error>) -> Void) {
        guard AISettings.shared.isConfigured,
              let url = AISettings.shared.resolvedEndpoint else {
            completion(.failure(AIError.notConfigured))
            return
        }
        guard let req = buildRequest(url: url, messages: messages, stream: false) else {
            completion(.failure(AIError.parseFailed("请求构造失败")))
            return
        }
        let s = URLSession(configuration: .default)
        s.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(.failure(err)); return }
                guard let http = resp as? HTTPURLResponse, let data = data else {
                    completion(.failure(AIError.parseFailed("无响应"))); return
                }
                if http.statusCode != 200 {
                    let msg = String(data: data, encoding: .utf8) ?? ""
                    completion(.failure(AIError.httpError(http.statusCode, String(msg.prefix(300)))))
                    return
                }
                if let text = Self.extractContent(from: data) {
                    completion(.success(text))
                } else {
                    completion(.failure(AIError.parseFailed("choices 结构异常")))
                }
            }
        }.resume()
    }

    // MARK: - 流式

    /// 流式对话。每收到一段增量文本调用 onDelta，结束时调用 completion。
    func chatStream(messages: [Message],
                    onReasoning: ((String) -> Void)? = nil,
                    onDelta: @escaping (String) -> Void,
                    completion: @escaping (Result<String, Error>) -> Void) {
        guard AISettings.shared.isConfigured,
              let url = AISettings.shared.resolvedEndpoint else {
            completion(.failure(AIError.notConfigured))
            return
        }
        guard let req = buildRequest(url: url, messages: messages, stream: true) else {
            completion(.failure(AIError.parseFailed("请求构造失败")))
            return
        }

        // 重置状态
        accumulated = ""
        reasoning = ""
        buffer = ""
        httpStatusCode = 0
        errorBody = Data()
        rawStreamBody = Data()
        isSSE = true
        self.onDelta = onDelta
        self.onReasoning = onReasoning
        self.onComplete = completion

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AISettings.shared.timeout
        let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = s
        let t = s.dataTask(with: req)
        self.task = t

        // 空闲超时看门狗：每 2s 检查一次，连续无数据超限则强制中断
        self.lastDataTime = Date().timeIntervalSince1970
        self.timeoutForced = false
        self.idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.session != nil else { return }
            let idle = Date().timeIntervalSince1970 - self.lastDataTime
            if idle > self.idleTimeout {
                print("[AIClient] idle timeout (\(Int(idle))s no data), force interrupt")
                self.timeoutForced = true
                self.task?.cancel()
            }
        }
        t.resume()
    }

    // MARK: - 请求构造

    private func buildRequest(url: URL, messages: [Message], stream: Bool) -> URLRequest? {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(AISettings.shared.apiKey)", forHTTPHeaderField: "Authorization")
        if stream {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        req.timeoutInterval = AISettings.shared.timeout

        var body: [String: Any] = [
            "model": AISettings.shared.model,
            "messages": messages.map { msg in
                if let img = msg.imageBase64, !img.isEmpty {
                    // 多模态：文本 + 图片
                    return [
                        "role": msg.role,
                        "content": [
                            ["type": "text", "text": msg.content],
                            ["type": "image_url", "image_url": ["url": img]]
                        ]
                    ]
                }
                return ["role": msg.role, "content": msg.content]
            },
            "temperature": AISettings.shared.temperature,
            // 生成的小程序包含多个完整文件（index.html/icon.svg/多页），
            // 输出可能很长；给足上限防止截断导致 JSON 解析失败
            "max_tokens": 16384
        ]
        if stream { body["stream"] = true }

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        return req
    }

    private static func extractContent(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }
}

// MARK: - 流式 SSE 解析

extension AIClient: URLSessionDataDelegate {

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            httpStatusCode = http.statusCode
            let ct = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            isSSE = ct.contains("event-stream")
            print("[AIClient] response status=\(http.statusCode) content-type=\(ct) isSSE=\(isSSE)")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // 收到任何数据都重置空闲计时
        lastDataTime = Date().timeIntervalSince1970
        // 非 200 时把 body 攒起来，最后报错
        if httpStatusCode != 0 && httpStatusCode != 200 {
            errorBody.append(data)
            return
        }

        // 非 SSE（一次性 JSON）：全部攒起来，结束时一次性解析
        if !isSSE {
            rawStreamBody.append(data)
            return
        }

        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk

        // SSE：按行分割，最后一行可能不完整，留到下次
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<nl])
            buffer = String(buffer[buffer.index(after: nl)...])
            handleSSELine(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if self.timeoutForced {
                self.finish(.failure(AIError.timeout))
                return
            }
            if let err = error as NSError?, err.code == NSURLErrorCancelled {
                self.finish(.failure(AIError.cancelled))
                return
            }
            if let err = error {
                self.finish(.failure(err))
                return
            }
            if self.httpStatusCode != 200 {
                let msg = String(data: self.errorBody, encoding: .utf8) ?? ""
                self.finish(.failure(AIError.httpError(self.httpStatusCode, String(msg.prefix(300)))))
                return
            }

            // 非 SSE 响应：把完整 JSON 当一次 delta 处理
            if !self.isSSE && !self.rawStreamBody.isEmpty {
                if let text = Self.extractContent(from: self.rawStreamBody) {
                    self.accumulated = text
                    self.onDelta?(text)
                    self.finish(.success(text))
                    return
                }
                // 也可能是 OpenAI 兼容的流式包装，但 Content-Type 错了——再试一次 SSE 解析
                if let str = String(data: self.rawStreamBody, encoding: .utf8) {
                    for line in str.split(separator: "\n") {
                        self.handleSSELine(String(line))
                    }
                    if !self.accumulated.isEmpty {
                        self.finish(.success(self.accumulated))
                        return
                    }
                }
                let preview = String(data: self.rawStreamBody.prefix(300), encoding: .utf8) ?? ""
                self.finish(.failure(AIError.parseFailed("无法解析响应: \(preview)")))
                return
            }

            if self.accumulated.isEmpty {
                self.finish(.failure(AIError.emptyResponse))
            } else {
                self.finish(.success(self.accumulated))
            }
        }
    }

    private func handleSSELine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("data:") else { return }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // 错误响应可能长这样：{"error":{"message":"..."}}
        if let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            DispatchQueue.main.async { self.finish(.failure(AIError.parseFailed(msg))) }
            return
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any] else { return }

        // 推理模型的思维链
        if let rc = delta["reasoning_content"] as? String, !rc.isEmpty {
            reasoning += rc
            DispatchQueue.main.async { self.onReasoning?(rc) }
        }

        // 正文
        if let content = delta["content"] as? String, !content.isEmpty {
            accumulated += content
            DispatchQueue.main.async { self.onDelta?(content) }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        idleTimer?.invalidate()
        idleTimer = nil
        session?.invalidateAndCancel()
        session = nil
        task = nil
        onDelta = nil
        onReasoning = nil
        onComplete?(result)
        onComplete = nil
    }
}
