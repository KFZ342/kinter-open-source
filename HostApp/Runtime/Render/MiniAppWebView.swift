import UIKit
import WebKit

/// 小程序 WebView 运行单元。
///
/// 引擎升级要点：
/// 1. **实例池化**：WKWebView 创建最贵的是 WebContent 进程启动（200ms+），
///    关闭的小程序回池复用，下次启动直接跳过进程创建，大幅降低启动延迟。
/// 2. **WKProcessPool 共享**：所有 WebView 共享进程池，降低整体内存占用。
/// 3. **崩溃自动恢复**：WebContent 进程被杀（系统回收/JS 内存爆炸）时自动 reload，
///    最多 3 次，避免白屏。
/// 4. **内存警告回收**：系统内存吃紧时清空空闲池，把内存还给系统。
final class MiniAppWebView: UIView, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var bridge: BridgeMessageHandler!
    /// 本会话的能力网关（会话级，复用 WebView 时换新实例）
    private(set) var gateway = CapabilityGateway()
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

    /// WebContent 崩溃且重试耗尽时回调（供上层提示）
    var onWebContentCrash: (() -> Void)?

    // MARK: - 实例池

    private static var pool: [MiniAppWebView] = []
    private static let poolLimit = 2
    private static let poolLock = NSLock()
    private static var memoryObserverInstalled = false

    /// 取一个可用的运行单元：优先复用池内实例（跳过 WebView 创建），否则新建。
    static func dequeue() -> MiniAppWebView {
        installMemoryWarningObserverIfNeeded()
        poolLock.lock()
        let reused = pool.popLast()
        poolLock.unlock()
        if let reused = reused {
            reused.resetForReuse()
            return reused
        }
        return MiniAppWebView(frame: .zero)
    }

    /// 运行结束回池。超出容量上限的直接释放（ARC 兜底）。
    static func recycle(_ view: MiniAppWebView) {
        view.prepareForReuse()
        poolLock.lock()
        if pool.count < poolLimit {
            pool.append(view)
            poolLock.unlock()
            return
        }
        poolLock.unlock()
        // 池满：不再持有，ARC 释放
    }

    /// 系统内存紧张时清空空闲池
    static func emptyPool() {
        poolLock.lock()
        pool.removeAll()
        poolLock.unlock()
    }

    private static func installMemoryWarningObserverIfNeeded() {
        guard !memoryObserverInstalled else { return }
        memoryObserverInstalled = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { _ in
            MiniAppWebView.emptyPool()
        }
    }

    // MARK: - 复用生命周期

    /// 回池前：停加载、清回调、摘导航代理，避免残留状态串到下一个会话。
    private func prepareForReuse() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        onJavascriptLog = nil
        onWebContentCrash = nil
        progress.progress = 0
        progress.isHidden = true
    }

    /// 出池后：重置会话状态、重建桥接与注入（脚本走缓存，开销极小）。
    private func resetForReuse() {
        guard let webView = webView else { return }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: BridgeMessageHandler.handlerName)
        controller.removeScriptMessageHandler(forName: "jslog")
        controller.removeAllUserScripts()

        gateway = CapabilityGateway()
        let handler = BridgeMessageHandler(webView: webView, gateway: gateway)
        controller.add(handler, name: BridgeMessageHandler.handlerName)
        controller.add(JSLogHandler(owner: self), name: "jslog")
        self.bridge = handler

        injectSDK(into: controller)

        webView.navigationDelegate = self
        crashCount = 0
        progress.progress = 0
        progress.isHidden = false
    }

    // MARK: - WebContent 崩溃恢复

    private var crashCount = 0
    private static let maxCrashRecovery = 3

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // 首次崩溃大多是系统内存回收，直接 reload 恢复；连续崩溃说明页面本身有问题
        crashCount += 1
        if crashCount <= Self.maxCrashRecovery {
            webView.reload()
        } else {
            onWebContentCrash?()
        }
    }

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
            // 批量：[[level, message], ...]（宽松解析，杜绝桥接失败静默吞日志）
            if let batch = body["batch"] as? [[Any]] {
                for pair in batch where pair.count >= 2 {
                    let lv = pair[0] as? String ?? "log"
                    let msg: String
                    if let s = pair[1] as? String {
                        msg = s
                    } else {
                        msg = String(describing: pair[1])
                    }
                    owner?.onJavascriptLog?(lv, msg)
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
        // 全部 WebView 共享同一进程池：降低内存、加快进程复用
        config.processPool = Self.sharedProcessPool

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
        wv.navigationDelegate = self
        injectSDK(into: controller)
    }

    private func injectSDK(into controller: WKUserContentController) {
        // 先注入 KTML 编译器（在 wx 之前，因为 wx 依赖页面已就绪）
        if let js = Self.sdkSource("ktml") {
            controller.addUserScript(WKUserScript(source: js,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        } else {
            print("[Render] ktml.js not found in bundle")
        }

        // 再注入 wx SDK
        guard let js = Self.sdkSource("wx") else {
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

    // MARK: - SDK 源码缓存

    /// Bundle 内 SDK JS 源码只读一次，全部 WebView 会话复用。
    /// 避免每次创建 WebView 都重新做文件 I/O（ktml.js + wx.js 各一次全量读取）。
    private static var sdkCache: [String: String] = [:]
    private static let sdkLock = NSLock()

    private static func sdkSource(_ name: String) -> String? {
        sdkLock.lock()
        defer { sdkLock.unlock() }
        if let cached = sdkCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        sdkCache[name] = js
        return js
    }
}

/// 共享 WebKit 进程池（全部 WebView 复用同一组 WebContent 进程）
extension MiniAppWebView {
    private static let sharedProcessPool = WKProcessPool()
}
