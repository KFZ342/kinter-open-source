import UIKit
import WebKit

/// 把内联 SVG 渲染成 PNG。
/// 用离屏 WKWebView 加载 SVG，等渲染完成后截图。
final class SVGIconRenderer: NSObject {

    /// 渲染 SVG 为 UIImage。回调在主线程。
    static func render(svg: String, size: CGFloat = 512,
                       completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.main.async {
            let html = """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8">
            <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
                width: \(Int(size))px; height: \(Int(size))px;
                overflow: hidden; background: transparent;
            }
            body > svg, body > * > svg {
                width: 100% !important;
                height: 100% !important;
                display: block;
            }
            </style></head>
            <body>\(svg)</body></html>
            """

            let frame = CGRect(x: 0, y: 0, width: size, height: size)
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = false

            let webView = WKWebView(frame: frame, configuration: config)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false

            let host = RenderHost(size: size, completion: completion)
            webView.navigationDelegate = host

            // 放到屏幕外。WKWebView 必须在 window 里才会正常渲染。
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                completion(nil)
                return
            }
            webView.frame = CGRect(x: -size - 100, y: 0, width: size, height: size)
            window.addSubview(webView)

            host.attach(webView: webView, window: window)
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// 每个渲染任务一个宿主对象，负责等加载完成、截图、清理。
    private final class RenderHost: NSObject, WKNavigationDelegate {
        let size: CGFloat
        let completion: (UIImage?) -> Void
        weak var webView: WKWebView?
        weak var window: UIWindow?
        private var finished = false

        init(size: CGFloat, completion: @escaping (UIImage?) -> Void) {
            self.size = size
            self.completion = completion
            super.init()
        }

        func attach(webView: WKWebView, window: UIWindow) {
            self.webView = webView
            self.window = window
            // 防止 RenderHost 被提前释放
            objc_setAssociatedObject(webView, &hostKey, self, .OBJC_ASSOCIATION_RETAIN)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 等一帧，确保 SVG 绘制完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.snapshot()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(nil)
        }

        private func snapshot() {
            guard let webView = webView else { finish(nil); return }
            let cfg = WKSnapshotConfiguration()
            cfg.rect = CGRect(x: 0, y: 0, width: size, height: size)
            cfg.snapshotWidth = NSNumber(value: Double(size))
            cfg.afterScreenUpdates = true

            webView.takeSnapshot(with: cfg) { image, error in
                if let image = image, image.size.width > 0 {
                    self.finish(image)
                } else {
                    self.finish(nil)
                }
            }
        }

        private func finish(_ image: UIImage?) {
            guard !finished else { return }
            finished = true
            webView?.navigationDelegate = nil
            webView?.removeFromSuperview()
            webView = nil
            completion(image)
        }
    }
}

private var hostKey: UInt8 = 0
