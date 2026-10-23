import UIKit
import AVFoundation

final class QRScanProvider: NSObject, CapabilityProvider {
    static var capability: String { "qrScan" }
    static var level: CapabilityLevel { .l1 }
    required override init() { super.init() }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "scan" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.userDenied("camera"))) }
                return
            }
            DispatchQueue.main.async {
                guard let top = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                    .first else {
                    completion(.failure(.providerError("no presenter")))
                    return
                }
                let vc = QRScannerViewController()
                vc.onResult = { result in
                    top.dismiss(animated: true)
                    switch result {
                    case .success(let text):
                        completion(.success(["text": text]))
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
                vc.modalPresentationStyle = .fullScreen
                top.presentSafely(vc, animated: true)
            }
        }
    }
}

/// 极简扫码页。
final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onResult: ((Result<String, GatewayError>) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupOverlay()
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onResult?(.failure(.unsupported("camera")))
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr, .ean13, .ean8, .code128, .code39, .code93, .upce]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        self.preview = layer

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    private func setupOverlay() {
        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeBtn.widthAnchor.constraint(equalToConstant: 36),
            closeBtn.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !handled, let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let text = obj.stringValue else { return }
        handled = true
        session.stopRunning()
        onResult?(.success(text))
    }

    @objc private func close() {
        session.stopRunning()
        onResult?(.failure(.userDenied("qrScan")))
    }
}
