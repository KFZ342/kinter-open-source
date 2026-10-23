import UIKit

final class ClipboardImageProvider: CapabilityProvider {
    static var capability: String { "clipboardImage" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        DispatchQueue.main.async {
            switch method {
            case "get":
                guard let img = UIPasteboard.general.image,
                      let data = img.pngData() else {
                    completion(.failure(.providerError("剪贴板中没有图片")))
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("paste_\(UUID().uuidString).png")
                do {
                    try data.write(to: url)
                    completion(.success([
                        "path": url.path,
                        "size": data.count,
                        "width": Int(img.size.width),
                        "height": Int(img.size.height)
                    ]))
                } catch {
                    completion(.failure(.providerError("保存失败")))
                }

            case "set":
                var img: UIImage?
                if let path = params["path"] as? String {
                    img = UIImage(contentsOfFile: path)
                } else if let b64 = params["base64"] as? String,
                          let d = Data(base64Encoded: b64) {
                    img = UIImage(data: d)
                }
                guard let image = img else {
                    completion(.failure(.invalidParams("path 或 base64 必填")))
                    return
                }
                UIPasteboard.general.image = image
                completion(.success(["ok": true]))

            case "hasImage":
                completion(.success(["hasImage": UIPasteboard.general.hasImages]))

            default:
                completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            }
        }
    }
}
