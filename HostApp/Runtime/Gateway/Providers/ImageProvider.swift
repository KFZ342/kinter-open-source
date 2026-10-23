import UIKit

final class ImageProvider: CapabilityProvider {
    static var capability: String { "image" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "compress" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let path = params["path"] as? String else {
            completion(.failure(.invalidParams("path 必填"))); return
        }
        let quality = params["quality"] as? CGFloat ?? 0.7
        let maxWidth = params["maxWidth"] as? CGFloat ?? 1920

        guard let raw = UIImage(contentsOfFile: path) else {
            completion(.failure(.invalidParams("图片不存在或无法读取"))); return
        }

        // 按最长边等比缩放
        let w = raw.size.width, h = raw.size.height
        let longest = max(w, h)
        var target = raw
        if longest > maxWidth {
            let scale = maxWidth / longest
            let newSize = CGSize(width: w * scale, height: h * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            target = renderer.image { _ in
                raw.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        guard let jpeg = target.jpegData(compressionQuality: max(0.1, min(quality, 1.0))) else {
            completion(.failure(.providerError("压缩失败"))); return
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmp_\(UUID().uuidString).jpg")
        do {
            try jpeg.write(to: out)
            let origSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            completion(.success([
                "path": out.path,
                "size": jpeg.count,
                "originalSize": origSize,
                "width": Int(target.size.width),
                "height": Int(target.size.height)
            ]))
        } catch {
            completion(.failure(.providerError("保存失败")))
        }
    }
}
