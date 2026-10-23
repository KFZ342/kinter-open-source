import UIKit
import CoreImage

final class QRGenerateProvider: CapabilityProvider {
    static var capability: String { "qrGenerate" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "generate" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let text = params["text"] as? String, !text.isEmpty else {
            completion(.failure(.invalidParams("text 必填")))
            return
        }
        let size = params["size"] as? CGFloat ?? 300

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            completion(.failure(.providerError("filter 不可用")))
            return
        }
        filter.setValue(text.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            completion(.failure(.providerError("生成失败")))
            return
        }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            completion(.failure(.providerError("渲染失败")))
            return
        }
        let image = UIImage(cgImage: cg)
        guard let png = image.pngData() else {
            completion(.failure(.providerError("编码失败")))
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qr_\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            completion(.success(["path": url.path, "size": Int(size)]))
        } catch {
            completion(.failure(.providerError("保存失败")))
        }
    }
}
