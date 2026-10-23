import UIKit
import PhotosUI

final class PhotoProvider: NSObject, CapabilityProvider, PHPickerViewControllerDelegate {
    static var capability: String { "photo" }
    static var level: CapabilityLevel { .l1 }

    private var completion: ((Result<Any, GatewayError>) -> Void)?

    required override init() { super.init() }

    func invoke(method: String, params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "chooseMedia" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let top = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            completion(.failure(.providerError("no presenter")))
            return
        }
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = (params["count"] as? Int) ?? 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        self.completion = completion
        top.presentSafely(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            completion?(.failure(.userDenied("photo")))
            completion = nil
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] obj, err in
            DispatchQueue.main.async {
                guard let image = obj as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) else {
                    self?.completion?(.failure(.providerError("load failed: \(err?.localizedDescription ?? "")")))
                    self?.completion = nil
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("photo_\(UUID().uuidString).jpg")
                do {
                    try data.write(to: url)
                    self?.completion?(.success(["tempFilePaths": [url.path]]))
                } catch {
                    self?.completion?(.failure(.providerError("write failed")))
                }
                self?.completion = nil
            }
        }
    }
}
