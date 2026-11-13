import UIKit
import AVFoundation

final class CameraProvider: NSObject, CapabilityProvider, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static var capability: String { "camera" }
    static var level: CapabilityLevel { .l1 }

    private var completion: ((Result<Any, GatewayError>) -> Void)?
    private weak var presenter: UIViewController?

    required override init() { super.init() }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "chooseImage" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        // 上一次拍照流程尚未结束：拒绝并发调用，避免新回调覆盖旧回调、picker 重复弹出。
        guard self.completion == nil else {
            completion(.failure(.providerError("camera busy")))
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            completion(.failure(.unsupported("camera")))
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            completion(.failure(.permissionDenied("camera")))
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else {
                    completion(.failure(.userDenied("camera")))
                    return
                }
                self?.presentPicker(params: params, completion: completion)
            }
        }
    }

    private func presentPicker(params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let top = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            self.completion = nil
            completion(.failure(.providerError("no presenter")))
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = false
        self.presenter = top
        self.completion = completion
        top.presentSafely(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.9) else {
            completion?(.failure(.providerError("image encode failed")))
            completion = nil
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cam_\(UUID().uuidString).jpg")
        do {
            try data.write(to: url)
            // 额外给一份压缩后的 data URL：小程序页面可直接 <img> 预览，Web 端也能显示
            let preview = image.preparingThumbnail(of: CGSize(width: 1280, height: 1280)) ?? image
            var payload: [String: Any] = ["tempFilePaths": [url.path],
                                          "size": data.count,
                                          "width": Int(image.size.width),
                                          "height": Int(image.size.height)]
            if let thumb = preview.jpegData(compressionQuality: 0.7) {
                payload["base64"] = "data:image/jpeg;base64," + thumb.base64EncodedString()
            }
            completion?(.success(payload))
        } catch {
            completion?(.failure(.providerError("save failed: \(error)")))
        }
        completion = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        completion?(.failure(.userDenied("camera")))
        completion = nil
    }
}
