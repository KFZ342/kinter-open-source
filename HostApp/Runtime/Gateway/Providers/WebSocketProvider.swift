import Foundation

/// WebSocket 长连接。支持 connect / send / close，
/// 消息与状态变化通过事件推送回 JS：
/// - websocket.open
/// - websocket.message  { data: String }
/// - websocket.close    { code: Int }
/// - websocket.error    { message: String }
final class WebSocketProvider: NSObject, CapabilityProvider, URLSessionWebSocketDelegate {
    static var capability: String { "websocket" }
    static var level: CapabilityLevel { .l0 }
    required override init() { super.init() }

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    /// 由 Runner 注入
    var emitter: ((String, Any) -> Void)?

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "connect":
            guard let urlStr = params["url"] as? String, let url = URL(string: urlStr) else {
                completion(.failure(.invalidParams("url 必填"))); return
            }
            closeExisting()
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            let t = s.webSocketTask(with: url)
            self.session = s
            self.task = t
            t.resume()
            listen()
            completion(.success(["ok": true, "url": urlStr]))

        case "send":
            guard let task = task else {
                completion(.failure(.providerError("未连接"))); return
            }
            guard let text = params["data"] as? String else {
                completion(.failure(.invalidParams("data 必填"))); return
            }
            task.send(.string(text)) { err in
                if let err = err {
                    completion(.failure(.providerError(err.localizedDescription)))
                } else {
                    completion(.success(["ok": true]))
                }
            }

        case "close":
            let code = params["code"] as? Int ?? 1000
            task?.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure,
                         reason: nil)
            closeExisting()
            completion(.success(["ok": true]))

        case "isOpen":
            completion(.success(["open": task?.state == .running]))

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let s):
                    self.emitter?("websocket.message", ["data": s])
                case .data(let d):
                    let b64 = d.base64EncodedString()
                    self.emitter?("websocket.message", ["data": b64, "binary": true])
                @unknown default: break
                }
                self.listen()
            case .failure(let err):
                self.emitter?("websocket.error", ["message": err.localizedDescription])
            }
        }
    }

    private func closeExisting() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        self.emitter?("websocket.open", ["protocol": `protocol` ?? ""])
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        self.emitter?("websocket.close", ["code": closeCode.rawValue])
    }
}
