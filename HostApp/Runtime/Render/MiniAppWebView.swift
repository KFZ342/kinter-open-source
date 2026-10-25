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

    /// JS 日志回调（level: log / info / warn / error / debug）
    var onJavascriptLog: ((String, String) -> Void)?

    /// 接收 JS console 日志的轻量 handler
    private final class JSLogHandler: NSObject, WKScriptMessageHandler {
        weak var owner: MiniAppWebView?
        init(owner: MiniAppWebView) {
            self.owner = owner
            super.init()
        }
        func userContentController(_ ucc: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "jslog",
                  let body = message.body as? [String: Any] else { return }
            // 批量：[[level, message], ...]
            if let batch = body["batch"] as? [[String]] {
                for pair in batch where pair.count >= 2 {
                    owner?.onJavascriptLog?(pair[0], pair[1])
                }
                return
            }
            // 兼容单条：{level, message}
            if let level = body["level"] as? String,
               let text = body["message"] as? String {
                owner?.onJavascriptLog?(level, text)
            }
        }
    }

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
        // 停止加载并移除导航代理，及时释放 WebKit 进程资源
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
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
        controller.add(JSLogHandler(owner: self), name: "jslog")

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

        // 最后注入日志钩子：重写 console + 捕获未处理异常，批量上报到原生 jslog
        // （高频日志合并成批量 postMessage，避免 WebKit 消息过密丢失）
        let logHook = """
        (function () {
          if (window.__kinterLogInstalled) return;
          window.__kinterLogInstalled = true;

          var pending = [];
          var timer = null;
          function flush() {
            timer = null;
            if (!pending.length) return;
            var batch = pending;
            pending = [];
            try { webkit.messageHandlers.jslog.postMessage({ batch: batch }); } catch (e) {}
          }
          function send(level, message) {
            pending.push([level, message]);
            if (pending.length >= 64) { flush(); return; }
            if (!timer) timer = setTimeout(flush, 16);
          }

          function fmt(args) {
            return Array.prototype.map.call(args, function (a) {
              try {
                if (typeof a === 'string') return a;
                if (a === undefined) return 'undefined';
                if (a === null) return 'null';
                if (typeof a === 'object') return JSON.stringify(a);
                return String(a);
              } catch (e) { return '[unserializable]'; }
            }).join(' ');
          }
          ['log', 'info', 'warn', 'error', 'debug'].forEach(function (lv) {
            var orig = (typeof console[lv] === 'function') ? console[lv].bind(console) : function () {};
            console[lv] = function () {
              var m = fmt(arguments);
              if (m.length > 4000) m = m.slice(0, 4000) + '…';
              send(lv, m);
              orig.apply(console, arguments);
            };
          });
          window.onerror = function (msg, src, line, col) {
            send('error', msg + ' @ ' + (src || '') + ':' + line + ':' + col);
            flush();
          };
          window.addEventListener('unhandledrejection', function (e) {
            var r = e.reason;
            var m = (r && r.message) ? r.message : String(r);
            send('error', 'Unhandled rejection: ' + m);
            flush();
          });
          window.addEventListener('beforeunload', flush);
        })();
        """
        controller.addUserScript(WKUserScript(source: logHook,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
    }
}
