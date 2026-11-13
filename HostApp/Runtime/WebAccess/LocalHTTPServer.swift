import Foundation
import Network

/// 一条已解析的 HTTP/1.1 请求。
struct HTTPRequest {
    var method: String
    let path: String
    let query: [String: String]
    /// 头名统一小写，取值保持原样
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var jsonBody: [String: Any]? {
        guard !body.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return obj
    }

    func queryValue(_ name: String) -> String? { query[name] }
}

/// 一条要写回浏览器的响应。
struct HTTPResponse {
    var status: Int
    var reason: String
    var headers: [String: String]
    var body: Data

    init(status: Int, reason: String = "", headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.reason = reason.isEmpty ? HTTPResponse.defaultReason(status) : reason
        self.headers = headers
        self.body = body
    }

    static func defaultReason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default:  return "Status \(status)"
        }
    }

    // MARK: - 构造快捷方法

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data: Data
        if let d = try? JSONSerialization.data(withJSONObject: object, options: []) {
            data = d
        } else {
            data = Data("{\"ok\":false,\"error\":{\"code\":\"encode_failed\",\"message\":\"响应序列化失败\"}}".utf8)
        }
        return HTTPResponse(status: status,
                            headers: ["Content-Type": "application/json; charset=utf-8"],
                            body: data)
    }

    static func text(_ string: String, status: Int = 200,
                     contentType: String = "text/plain; charset=utf-8") -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": contentType],
                     body: Data(string.utf8))
    }

    static func html(_ string: String, status: Int = 200) -> HTTPResponse {
        text(string, status: status, contentType: "text/html; charset=utf-8")
    }

    static func empty(status: Int = 204) -> HTTPResponse {
        HTTPResponse(status: status, body: Data())
    }

    static func failure(_ status: Int, code: String, message: String) -> HTTPResponse {
        json(["ok": false, "error": ["code": code, "message": message]], status: status)
    }

    /// 序列化为完整 HTTP 报文。统一使用 Connection: close，浏览器/客户端都兼容。
    /// omitBody 用于 HEAD：只回头部，Content-Length 仍是 GET 时的长度。
    func serialized(omitBody: Bool = false) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        for (k, v) in allHeaders {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"
        var out = Data(head.utf8)
        if !omitBody { out.append(body) }
        return out
    }
}

/// 统一的安全响应头与同源判定。
///
/// 安全约定：
/// - 不再下发 `Access-Control-Allow-Origin: *`：控制台页面与接口同源，本就不需要 CORS；
///   只有当请求带 `Origin` 且与 `Host` 同源时才回显该 Origin，避免任意网站跨域读取带令牌的响应。
/// - 鉴权走自定义头 / HttpOnly Cookie（SameSite=Strict），CORS 放开不作为安全边界。
enum WebHTTP {

    /// 允许的 HTTP 方法白名单。
    static let allowedMethods: Set<String> = ["GET", "POST", "HEAD", "OPTIONS"]

    /// 从 Host 头取服务端源（scheme://host:port）。
    static func hostOrigin(of request: HTTPRequest) -> String? {
        guard let host = request.header("host")?.lowercased(), !host.isEmpty else { return nil }
        return "http://\(host)"
    }

    /// 判断请求的 Origin 是否与本服务同源；无 Origin 头（同源导航 / 命令行调用）不做拦截。
    static func isSameOrigin(_ request: HTTPRequest) -> Bool {
        guard let origin = request.header("origin")?.lowercased() else { return true }
        guard let hostOrigin = hostOrigin(of: request) else { return false }
        return origin == hostOrigin
    }

    /// 同源时回显 Origin 并加 Vary: Origin；跨源不带 ACAO。
    static func withOrigin(_ response: HTTPResponse, for request: HTTPRequest) -> HTTPResponse {
        var r = response
        if let origin = request.header("origin")?.lowercased(),
           let hostOrigin = hostOrigin(of: request), origin == hostOrigin {
            r.headers["Access-Control-Allow-Origin"] = origin
            r.headers["Vary"] = "Origin"
        }
        return r
    }

    static func cors(_ response: HTTPResponse) -> HTTPResponse {
        var r = response
        r.headers["Cache-Control"] = r.headers["Cache-Control"] ?? "no-store"
        r.headers["X-Content-Type-Options"] = "nosniff"
        r.headers["X-Frame-Options"] = "DENY"
        r.headers["Referrer-Policy"] = "no-referrer"
        r.headers["Content-Security-Policy"] = "frame-ancestors 'none'; base-uri 'self'"
        return r
    }

    /// 鉴权后接口响应的统一包装：安全头 + 同源 Origin 回显。
    static func authorized(_ response: HTTPResponse, for request: HTTPRequest) -> HTTPResponse {
        withOrigin(cors(response), for: request)
    }
}

/// 极轻量的 HTTP/1.1 服务端：只做 Kinter Web 访问需要的部分。
/// 设计取舍：
/// - 只处理「一个请求一条连接」（Connection: close），省掉 keep-alive 状态机；
/// - 只支持 Content-Length 定长请求体，不处理 chunked（浏览器 fetch/XHR 默认不会用 chunked 发请求）；
/// - 请求体上限 40 MB（ZIP 安装包），超过直接断开，防止被当成内存放大器。
final class LocalHTTPServer {

    enum ServerError: LocalizedError {
        case startTimeout
        case listenerFailed(String)
        case badPort

        var errorDescription: String? {
            switch self {
            case .startTimeout:            return "本地服务启动超时"
            case .listenerFailed(let s):   return "本地服务启动失败：\(s)"
            case .badPort:                 return "端口号无效"
            }
        }
    }

    typealias Handler = (HTTPRequest, @escaping (HTTPResponse) -> Void) -> Void

    private let handler: Handler
    private let queue = DispatchQueue(label: "com.kinter.webaccess.server", qos: .userInitiated)
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private(set) var isRunning = false

    /// 单条连接首包最长等待时间，防止半开连接吊死
    private let connectionDeadline: TimeInterval = 25
    /// 请求头已收到、请求体尚未到齐时的等待上限，防止慢速灌 body 占住连接
    private let bodyDeadline: TimeInterval = 15
    /// 请求已解析后等待业务响应的时间（长轮询 25s + 余量）
    private let responseDeadline: TimeInterval = 40
    /// 能力调用可能等用户交互，单独放宽
    private let invokeDeadline: TimeInterval = 180
    private let maxBodyBytes = 40 * 1024 * 1024

    // MARK: - 报文健壮性上限

    /// 请求行最大长度
    private static let maxRequestLineBytes = 8 * 1024
    /// 整个请求头区（含请求行）最大长度
    private static let maxHeaderBytes = 64 * 1024
    /// 单条连接允许的头字段数量
    private static let maxHeaderCount = 64
    /// 并发连接上限，超出直接拒绝，避免被占满 fd / 内存
    private let maxActiveConnections = 32

    private let connectionLock = NSLock()
    private var activeConnections = 0

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// 启动监听。preferredPort 传 0 表示由系统分配。
    @discardableResult
    func start(preferredPort: UInt16) throws -> UInt16 {
        stop()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // 不启用 AWDL / 临机互联通道，只走常规 Wi-Fi / 回环；NWListener 默认不注册 Bonjour/mDNS 广播。
        params.includePeerToPeer = false

        let endpointPort: NWEndpoint.Port
        if preferredPort == 0 {
            endpointPort = .any
        } else {
            guard let p = NWEndpoint.Port(rawValue: preferredPort) else { throw ServerError.badPort }
            endpointPort = p
        }

        let l = try NWListener(using: params, on: endpointPort)
        l.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        let sem = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        var startError: ServerError?

        l.stateUpdateHandler = { state in
            switch state {
            case .ready:
                boundPort = l.port?.rawValue ?? preferredPort
                sem.signal()
            case .failed(let error):
                startError = .listenerFailed(error.localizedDescription)
                sem.signal()
            case .cancelled:
                sem.signal()
            default:
                break
            }
        }

        l.start(queue: queue)
        if sem.wait(timeout: .now() + 3) == .timedOut {
            l.cancel()
            throw ServerError.startTimeout
        }
        if let e = startError {
            l.cancel()
            throw e
        }

        guard boundPort != 0 else {
            l.cancel()
            throw ServerError.startTimeout
        }

        listener = l
        port = boundPort
        isRunning = true
        NSLog("[WebAccess] 本地服务已监听 :%d", Int(boundPort))
        return boundPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = 0
    }

    /// 需要更长响应预算的路径：能力调用、包上传、商店下载
    static func longRunningPath(_ path: String) -> Bool {
        path == "/api/invoke"
            || path.hasPrefix("/api/apps/import")
            || path.hasPrefix("/api/apps/preview")
            || path.hasPrefix("/api/store/install")
            || path.hasPrefix("/api/store/refresh")
    }

    // MARK: - 连接

    private func accept(_ connection: NWConnection) {
        connectionLock.lock()
        let allowed = activeConnections < maxActiveConnections
        if allowed { activeConnections += 1 }
        connectionLock.unlock()

        guard allowed else {
            connection.start(queue: queue)
            let resp = HTTPResponse.failure(503, code: "too_many_connections",
                                            message: "并发连接数已达上限")
            connection.send(content: resp.serialized(), completion: .contentProcessed { _ in
                connection.cancel()
                self.releaseConnection()
            })
            return
        }

        connection.start(queue: queue)
        NSLog("[WebAccess] 收到连接 %@", String(describing: connection.endpoint))

        var buffer = Data()
        var responded = false
        var closed = false

        func close() {
            guard !closed else { return }
            closed = true
            connection.cancel()
            self.releaseConnection()
        }

        // 首包超时：连接建立后迟迟不发请求就断掉（防止半开连接占位）
        let idleItem = DispatchWorkItem { if !responded { close() } }
        queue.asyncAfter(deadline: .now() + connectionDeadline, execute: idleItem)
        // body 超时：请求头到齐后，body 必须在 bodyDeadline 内到齐，防止慢速灌体占住连接
        var bodyItem: DispatchWorkItem?

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { data, _, isComplete, error in
                if error != nil { close(); return }
                if let d = data, !d.isEmpty { buffer.append(d) }

                switch LocalHTTPServer.parse(buffer, maxBody: self.maxBodyBytes) {
                case .request(var request):
                    idleItem.cancel(); bodyItem?.cancel()
                    // HEAD 只是探头部，按 GET 路由但回包不带 body
                    let headOnly = request.method == "HEAD"
                    if headOnly { request.method = "GET" }
                    // 能力调用可能等用户操作（拍照、选图、授权弹窗），响应超时给宽一点
                    let responseItem = DispatchWorkItem { if !responded { close() } }
                    let budget = LocalHTTPServer.longRunningPath(request.path)
                        ? self.invokeDeadline : self.responseDeadline
                    self.queue.asyncAfter(deadline: .now() + budget, execute: responseItem)
                    self.handler(request) { response in
                        responded = true
                        responseItem.cancel()
                        let payload = response.serialized(omitBody: headOnly)
                        connection.send(content: payload, completion: .contentProcessed { _ in close() })
                    }

                case .needMore:
                    // 头区已到齐但 body 未到：挂 body 读取超时；否则继续等首包
                    if bodyItem == nil, buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                        let item = DispatchWorkItem { if !responded { close() } }
                        bodyItem = item
                        self.queue.asyncAfter(deadline: .now() + self.bodyDeadline, execute: item)
                    }
                    if buffer.count > self.maxBodyBytes {
                        // 请求体过大：直接回 413 后断开
                        responded = true
                        idleItem.cancel(); bodyItem?.cancel()
                        let resp = HTTPResponse.failure(413, code: "payload_too_large",
                                                        message: "请求体超过上限（40 MB）")
                        connection.send(content: resp.serialized(), completion: .contentProcessed { _ in close() })
                        return
                    }
                    if isComplete { close(); return }
                    receiveMore()

                case .reject(let resp):
                    responded = true
                    idleItem.cancel(); bodyItem?.cancel()
                    connection.send(content: resp.serialized(), completion: .contentProcessed { _ in close() })
                }
            }
        }

        receiveMore()
    }

    private func releaseConnection() {
        connectionLock.lock()
        activeConnections = max(0, activeConnections - 1)
        connectionLock.unlock()
    }

    // MARK: - 解析

    /// 解析结果：请求已就绪 / 数据还不够 / 请求非法（直接回错误并断开）。
    enum ParseOutcome {
        case request(HTTPRequest)
        case needMore
        case reject(HTTPResponse)
    }

    /// 返回 .needMore 表示数据还不够，需要继续收；.reject 表示请求非法，应回错误并断开。
    static func parse(_ data: Data, maxBody: Int) -> ParseOutcome {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            // 头区还没收齐；超过头长度上限直接拒绝，避免无限累积撑爆内存
            return data.count > maxHeaderBytes ? .reject(tooLargeHeader()) : .needMore
        }

        let headSlice = data[data.startIndex..<headerEnd.lowerBound]
        if headSlice.count > maxHeaderBytes { return .reject(tooLargeHeader()) }
        guard let headString = String(data: headSlice, encoding: .utf8) else {
            return .reject(badRequest("请求头不是合法 UTF-8"))
        }

        var lines = headString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .needMore }

        let requestLine = lines.removeFirst()
        if requestLine.utf8.count > maxRequestLineBytes { return .reject(tooLargeHeader()) }
        if requestLine.contains("\0") { return .reject(badRequest("请求行包含非法字符")) }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return .reject(badRequest("请求行格式非法")) }

        let method = String(parts[0]).uppercased()
        guard WebHTTP.allowedMethods.contains(method) else {
            return .reject(HTTPResponse.failure(405, code: "method_not_allowed",
                                                message: "不支持的方法：\(method)"))
        }
        let target = String(parts[1])

        guard lines.count <= maxHeaderCount else { return .reject(badRequest("请求头字段过多")) }

        var headers: [String: String] = [:]
        var contentLengthValues: [String] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            headers[name] = value
            if name == "content-length" { contentLengthValues.append(value) }
        }

        // chunked 传输不支持：直接拒绝，避免请求体走私 / 长度判定不一致
        if headers["transfer-encoding"] != nil {
            return .reject(badRequest("不支持 chunked 传输"))
        }

        // 多个 Content-Length 且取值不一致时拒绝（请求走私防护）
        if let first = contentLengthValues.first,
           contentLengthValues.contains(where: { $0 != first }) {
            return .reject(badRequest("Content-Length 重复且不一致"))
        }

        let clRaw = contentLengthValues.first ?? "0"
        guard !clRaw.isEmpty, clRaw.allSatisfy({ $0.isNumber }),
              let contentLength = Int(clRaw), contentLength >= 0 else {
            return .reject(badRequest("Content-Length 非法"))
        }
        if contentLength > maxBody {
            return .reject(HTTPResponse.failure(413, code: "payload_too_large",
                                                message: "请求体超过上限（40 MB）"))
        }

        let rawBody = data[headerEnd.upperBound...]
        if rawBody.count < contentLength { return .needMore }
        let body = Data(rawBody.prefix(contentLength))

        // 拆 path / query
        var path = target
        var queryString = ""
        if let qIndex = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<qIndex])
            queryString = String(target[target.index(after: qIndex)...])
        }
        // 绝对地址形式（代理风格）兼容
        if path.hasPrefix("http://") || path.hasPrefix("https://"),
           let comps = URLComponents(string: path) {
            path = comps.path
            if queryString.isEmpty { queryString = comps.query ?? "" }
        }
        if path.isEmpty { path = "/" }
        if path.contains("\0") { return .reject(badRequest("路径包含非法字符")) }

        var query: [String: String] = [:]
        for pair in queryString.split(separator: "&", omittingEmptySubsequences: true) {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
            if query[key] == nil { query[key] = value }
        }

        return .request(HTTPRequest(method: method, path: path, query: query, headers: headers, body: body))
    }

    private static func badRequest(_ message: String) -> HTTPResponse {
        HTTPResponse.failure(400, code: "bad_request", message: message)
    }

    private static func tooLargeHeader() -> HTTPResponse {
        HTTPResponse.failure(413, code: "header_too_large", message: "请求头超过长度上限")
    }
}

/// 本机局域网地址与二维码相关的小工具。
enum LocalNetworkInfo {

    /// 取当前 Wi-Fi / 有线网卡的 IPv4 地址（en0 优先）。
    static func primaryIPv4() -> String? {
        var candidates: [String: String] = [:]   // ifname -> address
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            defer { cursor = interface.ifa_next }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &hostname, socklen_t(hostname.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            if !ip.isEmpty { candidates[name] = ip }
        }

        if let en0 = candidates["en0"] { return en0 }
        // 退而求其次：任意非虚拟网卡
        for (name, ip) in candidates where !name.hasPrefix("utun") && !name.hasPrefix("bridge") {
            return ip
        }
        return candidates.values.first
    }

    /// 生成本地服务的可访问地址
    static func baseURL(port: UInt16) -> String? {
        guard let ip = primaryIPv4() else { return nil }
        return "http://\(ip):\(port)"
    }
}
