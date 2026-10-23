import UIKit
import Photos

final class SavePhotoProvider: CapabilityProvider {
    static var capability: String { "savePhoto" }
    static var level: CapabilityLevel { .l1 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "save" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        // 支持本地路径或 base64
        var image: UIImage?
        if let path = params["path"] as? String {
            image = UIImage(contentsOfFile: path)
        } else if let base64 = params["base64"] as? String,
                  let data = Data(base64Encoded: base64) {
            image = UIImage(data: data)
        }
        guard let img = image else {
            completion(.failure(.invalidParams("path 或 base64 必填")))
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(.userDenied("savePhoto"))) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            } completionHandler: { ok, err in
                DispatchQueue.main.async {
                    if ok { completion(.success(["ok": true])) }
                    else { completion(.failure(.providerError(err?.localizedDescription ?? "保存失败"))) }
                }
            }
        }
    }
}
