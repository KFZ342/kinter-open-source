import UIKit
import WebKit

/// 把本地 HTML 或 URL 渲染成 PDF。
/// 用 WKWebView 打印接口，比 UIGraphicsPDFRenderer 更保真（保留 CSS 排版）。
final class PDFProvider: NSObject, CapabilityProvider, WKNavigationDelegate {
    static var capability: String { "pdf" }
    static var level: CapabilityLevel { .l0 }
    required override init() { super.init() }

    private var webView: WKWebView?
    private var completion: ((Result<Any, GatewayError>) -> Void)?

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "generate" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard let path = params["path"] as? String else {
            completion(.failure(.invalidParams("path 必填"))); return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            completion(.failure(.invalidParams("文件不存在"))); return
        }

        self.completion = completion
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842), configuration: config)
        wv.navigationDelegate = self
        wv.isHidden = true
        self.webView = wv

        let url = URL(fileURLWithPath: path)
        wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 等渲染稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.render()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion?(.failure(.providerError(error.localizedDescription)))
        completion = nil
    }

    private func render() {
        guard let wv = webView else { return }
        let printConfig = WKPDFConfiguration()
        printConfig.rect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 @72dpi

        wv.createPDF(configuration: printConfig) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    let out = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pdf_\(UUID().uuidString).pdf")
                    do {
                        try data.write(to: out)
                        self.completion?(.success([
                            "path": out.path,
                            "size": data.count,
                            "pages": "auto"
                        ]))
                    } catch {
                        self.completion?(.failure(.providerError("保存失败")))
                    }
                case .failure(let err):
                    self.completion?(.failure(.providerError(err.localizedDescription)))
                }
                self.completion = nil
                self.webView = nil
            }
        }
    }
}
