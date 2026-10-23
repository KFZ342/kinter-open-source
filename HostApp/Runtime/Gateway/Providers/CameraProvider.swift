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
            completion?(.success(["tempFilePaths": [url.path]]))
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
