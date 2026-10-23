import UIKit
import AVFoundation

final class VideoRecordProvider: NSObject, CapabilityProvider, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static var capability: String { "videoRecord" }
    static var level: CapabilityLevel { .l1 }
    required override init() { super.init() }

    private var completion: ((Result<Any, GatewayError>) -> Void)?

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "record" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.userDenied("camera"))) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                DispatchQueue.main.async {
                    self.present(maxDuration: params["maxDuration"] as? TimeInterval ?? 60,
                                 completion: completion)
                }
            }
        }
    }

    private func present(maxDuration: TimeInterval, completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let top = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            completion(.failure(.providerError("no presenter")))
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = maxDuration
        picker.delegate = self
        self.completion = completion
        top.presentSafely(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let url = info[.mediaURL] as? URL else {
            completion?(.failure(.providerError("录制失败")))
            completion = nil; return
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("vid_\(UUID().uuidString).mov")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
            completion?(.success(["path": dest.path, "size": size]))
        } catch {
            completion?(.failure(.providerError("保存失败")))
        }
        completion = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        completion?(.failure(.userDenied("camera")))
        completion = nil
    }
}
