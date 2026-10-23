import UIKit
import WebKit

final class MiniAppWebView: UIView {
    private(set) var webView: WKWebView!
    private var bridge: BridgeMessageHandler!
    /// 本会话的能力网关
    let gateway = CapabilityGateway()
    var pageRouter: PageRouter? {
        get { bridge.pageRouter }
        set { bridge.pageRouter = newValue }
    }

    /// 应用级全局存储（由 Runner 注入）
    var appStore: AppStore? {
        get { bridge.appStore }
        set { bridge.appStore = newValue }
    }

    /// 拿到 bridge 引用，供 Runner 注入回调
    var bridgeForInterop: BridgeMessageHandler? { bridge }

    /// 拿到 bridge 引用，供 Runner 注入回调

    /// 向 JS 主动推送事件（供 Provider 使用）
    func bridgeEmit(event: String, data: Any) {
        bridge.emit(event: event, data: data)
    }
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var obs: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        obs?.invalidate()
    }

    private func setup() {
        // 关键修复：userContentController 必须在 WKWebView 初始化之前设置。
        // WKWebView(configuration:) 会复制配置，初始化后再赋值不会生效。
        let controller = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: .zero, configuration: config)
        let handler = BridgeMessageHandler(webView: wv, gateway: gateway)
        controller.add(handler, name: BridgeMessageHandler.handlerName)

        wv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wv)

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .systemBlue
        addSubview(progress)

        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: trailingAnchor),
            wv.topAnchor.constraint(equalTo: topAnchor),
            wv.bottomAnchor.constraint(equalTo: bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor),
            progress.topAnchor.constraint(equalTo: topAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2)
        ])

        obs = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            let p = Float(change.newValue ?? 0)
            self?.progress.progress = p
            self?.progress.isHidden = p >= 1.0
        }

        self.webView = wv
        self.bridge = handler
        injectSDK(into: controller)
    }

    private func injectSDK(into controller: WKUserContentController) {
        // 先注入 KTML 编译器（在 wx 之前，因为 wx 依赖页面已就绪）
        if let url = Bundle.main.url(forResource: "ktml", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: js,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        } else {
            print("[Render] ktml.js not found in bundle")
        }

        // 再注入 wx SDK
        guard let url = Bundle.main.url(forResource: "wx", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            print("[Render] wx.js not found in bundle")
            return
        }
        controller.addUserScript(WKUserScript(source: js,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
    }
}
