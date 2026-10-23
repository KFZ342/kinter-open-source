import UIKit

final class PrintProvider: CapabilityProvider {
    static var capability: String { "print" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "print" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let path = params["path"] as? String else {
            completion(.failure(.invalidParams("path 必填"))); return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            completion(.failure(.invalidParams("文件不存在"))); return
        }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        DispatchQueue.main.async {
            let info: UIPrintInfo
            let controller: UIPrintInteractionController

            if ext == "pdf", let data = try? Data(contentsOf: url) {
                controller = UIPrintInteractionController.shared
                info = UIPrintInfo(dictionary: nil)
                info.outputType = .general
                info.jobName = url.lastPathComponent
                controller.printInfo = info
                controller.printingItem = data
            } else if let img = UIImage(contentsOfFile: path) {
                controller = UIPrintInteractionController.shared
                info = UIPrintInfo(dictionary: nil)
                info.outputType = .photo
                info.jobName = url.lastPathComponent
                controller.printInfo = info
                controller.printingItem = img
            } else {
                completion(.failure(.invalidParams("仅支持 PDF 或图片")))
                return
            }

            let done: UIPrintInteractionController.CompletionHandler = { _, ok, err in
                if let err = err {
                    completion(.failure(.providerError(err.localizedDescription)))
                } else {
                    completion(.success(["ok": ok, "cancelled": !ok]))
                }
            }

            let presented: Bool
            if UIDevice.current.userInterfaceIdiom == .pad {
                presented = controller.present(from: CGRect(x: 0, y: 0, width: 1, height: 1),
                                              in: self.hostView(),
                                              animated: true,
                                              completionHandler: done)
            } else {
                presented = controller.present(animated: true, completionHandler: done)
            }
            if !presented {
                completion(.failure(.providerError("无法打开打印面板")))
            }
        }
    }

    /// 用于 iPad popover 锚点
    private func hostView() -> UIView {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        return window ?? UIView()
    }
}
