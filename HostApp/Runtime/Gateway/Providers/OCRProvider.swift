import UIKit
import Vision

final class OCRProvider: CapabilityProvider {
    static var capability: String { "ocr" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "recognize" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        var image: UIImage?
        if let path = params["path"] as? String {
            image = UIImage(contentsOfFile: path)
        } else if let base64 = params["base64"] as? String,
                  let data = Data(base64Encoded: base64) {
            image = UIImage(data: data)
        }
        guard let img = image, let cg = img.cgImage else {
            completion(.failure(.invalidParams("path 或 base64 必填")))
            return
        }
        let languages = params["langs"] as? [String] ?? ["zh-Hans", "en-US"]

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { req, err in
                if let err = err {
                    DispatchQueue.main.async { completion(.failure(.providerError(err.localizedDescription))) }
                    return
                }
                guard let results = req.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async { completion(.success(["lines": [String]()])) }
                    return
                }
                var lines: [[String: Any]] = []
                for obs in results {
                    guard let best = obs.topCandidates(1).first else { continue }
                    let bbox = obs.boundingBox
                    lines.append([
                        "text": best.string,
                        "confidence": best.confidence,
                        "x": bbox.minX,
                        "y": bbox.minY,
                        "w": bbox.width,
                        "h": bbox.height
                    ])
                }
                DispatchQueue.main.async { completion(.success(["lines": lines])) }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        }
    }
}
