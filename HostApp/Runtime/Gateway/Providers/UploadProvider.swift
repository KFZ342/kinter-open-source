import Foundation

final class UploadProvider: CapabilityProvider {
    static var capability: String { "upload" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "upload" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let urlStr = params["url"] as? String, let url = URL(string: urlStr) else {
            completion(.failure(.invalidParams("url 必填"))); return
        }
        guard let filePath = params["filePath"] as? String else {
            completion(.failure(.invalidParams("filePath 必填"))); return
        }
        guard FileManager.default.fileExists(atPath: filePath) else {
            completion(.failure(.invalidParams("文件不存在"))); return
        }
        let fieldName = params["field"] as? String ?? "file"
        let fileName = params["fileName"] as? String ?? URL(fileURLWithPath: filePath).lastPathComponent
        let mime = params["mime"] as? String ?? Self.mimeType(for: fileName)
        let extraFields = params["fields"] as? [String: String] ?? [:]
        let method_ = params["method"] as? String ?? "POST"

        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            completion(.failure(.providerError("无法读取文件"))); return
        }

        let boundary = "----MiniAppBoundary\(UUID().uuidString)"
        var body = Data()

        // 附加字段
        for (k, v) in extraFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(v)\r\n".data(using: .utf8)!)
        }

        // 文件字段
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = method_
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 60

        if let headers = params["headers"] as? [String: String] {
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(.providerError(err.localizedDescription))); return
                }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.success(["status": status, "body": text, "uploaded": fileData.count]))
            }
        }.resume()
    }

    private static func mimeType(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "json": return "application/json"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
