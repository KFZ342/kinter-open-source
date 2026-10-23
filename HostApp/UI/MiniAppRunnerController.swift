import UIKit

/// 运行已安装的小程序。模态呈现，右上角关闭按钮。
final class MiniAppRunnerController: UIViewController {

    private let app: InstalledApp
    /// 由多任务容器托管时设为 true，隐藏自身关闭按钮
    var isMultiTaskChild = false
    private var web: MiniAppWebView!
    private var manifest: MiniAppManifest?
    private let router = PageRouter()
    private let store = AppStore()

    init(app: InstalledApp) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 顶部自定义导航栏
        setupNavBar()

        web = MiniAppWebView(frame: .zero)
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        loadApp()
        setupKeyboardAvoidance()
    }

    // MARK: - 键盘避让

    private func setupKeyboardAvoidance() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ note: Notification) {
        guard let info = note.userInfo,
              let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        UIView.animate(withDuration: duration) {
            self.web.webView.scrollView.contentInset.bottom = overlap
            self.web.webView.scrollView.verticalScrollIndicatorInsets.bottom = overlap
        }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.25
        UIView.animate(withDuration: duration) {
            self.web.webView.scrollView.contentInset.bottom = 0
            self.web.webView.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 自定义导航栏

    private let navBar = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let iterateButton = UIButton(type: .system)

    private func setupNavBar() {
        navBar.backgroundColor = .secondarySystemBackground
        navBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBar)

        titleLabel.text = app.name
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(titleLabel)

        // 右上角关闭按钮：X 图标
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .systemGray
        closeButton.addTarget(self, action: #selector(closeApp), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = isMultiTaskChild
        navBar.addSubview(closeButton)

        // 迭代按钮（仅 AI 应用显示）
        iterateButton.setImage(UIImage(systemName: "sparkles"), for: .normal)
        iterateButton.tintColor = .systemPurple
        iterateButton.addTarget(self, action: #selector(iterateApp), for: .touchUpInside)
        iterateButton.translatesAutoresizingMaskIntoConstraints = false
        iterateButton.isHidden = !app.isAIGenerated
        navBar.addSubview(iterateButton)

        // 迭代按钮（仅 AI 应用显示）
        // 左上角刷新
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reloadButton.tintColor = .systemBlue
        reloadButton.addTarget(self, action: #selector(reloadPage), for: .touchUpInside)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(reloadButton)

        NSLayoutConstraint.activate([
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 52),

            reloadButton.leadingAnchor.constraint(equalTo: navBar.leadingAnchor, constant: 16),
            reloadButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 36),
            reloadButton.heightAnchor.constraint(equalToConstant: 36),

            iterateButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            iterateButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            iterateButton.widthAnchor.constraint(equalToConstant: 36),
            iterateButton.heightAnchor.constraint(equalToConstant: 36),


            closeButton.trailingAnchor.constraint(equalTo: navBar.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: reloadButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: iterateButton.leadingAnchor, constant: -8)
        ])
    }

    // MARK: - 加载

    /// 注入应用间调用能力
    private func installAppInterop() {
        // 拿到当前 webview 的 bridge，注入 onOpenApp
        guard let bridge = web.bridgeForInterop else { return }
        bridge.onOpenApp = { [weak self] targetAppId, params, completion in
            guard let self = self else { completion(false, "已释放"); return }
            guard targetAppId != self.app.appId else {
                completion(false, "不能打开自己")
                return
            }
            guard let target = AppLibrary.shared.app(id: targetAppId) else {
                completion(false, "应用未安装")
                return
            }
            // 记录参数，关闭当前后打开目标
            MiniAppLauncher.pendingParams[targetAppId] = params
            completion(true, nil)
            // 延迟一点，让 JS 收到成功回调后再切
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.closeAppAndOpenNext(target)
            }
        }
    }


    private func loadApp() {
        if let data = try? Data(contentsOf: app.manifestURL),
           let m = try? ManifestParser.parse(data: data) {
            manifest = m
        }
        if let m = manifest {
            web.gateway.setManifest(m)
        }
        // 读取待注入的启动参数
        if let p = MiniAppLauncher.takeParams(for: app.appId) {
            web.gateway.launchParams = p
        }
        web.gateway.setDisabledCapabilities(app.disabledCapabilities)

        // 入口完全由 manifest.pages[0] 决定，缺失时 router 内部会报错
        guard let entryPath = manifest?.pages.first, !entryPath.isEmpty else {
            showError("manifest 未声明入口页（pages 为空）")
            return
        }
        web.pageRouter = router
        web.appStore = store

        // 注入应用间调用
        installAppInterop()

        // 把 emit 能力注入给本会话的 Provider
        web.gateway.bindEmitters { [weak web] event, data in
            web?.bridgeEmit(event: event, data: data)
        }
        // 确保数据目录存在（用户可在 Files app 中浏览）
        app.ensureDataDirectory()
        do {
            try router.configure(webView: web.webView, rootDir: app.directory, entry: entryPath)
        } catch {
            showError("入口页加载失败：\(error.localizedDescription)")
        }
    }

    private func showError(_ text: String) {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }

    @objc private func reloadPage() { loadApp() }

    /// 打开迭代页：预填原描述，生成后覆盖本应用
    @objc private func iterateApp() {
        guard app.isAIGenerated else { return }
        let gen = AIGenerateViewController(iterateApp: app)
        let nav = UINavigationController(rootViewController: gen)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
    /// 容器销毁时调用，清理会话状态但不 dismiss。
    func forceCleanup() {
        web?.gateway.setDisabledCapabilities([])
        store.clear()
        HostPopup.dismissAll()
    }

    @objc private func closeApp() {
        closeAppAndOpenNext(nil)
    }

    private func closeAppAndOpenNext(_ next: InstalledApp?) {
        web.gateway.setDisabledCapabilities([])
        AppSettings.shared.lastOpenedAppId = nil
        // 关闭小程序时清空全局数据，避免影响下一次启动
        store.clear()
        // 断开事件推送，避免内存泄漏
        
        
        // 清掉可能残留的弹窗
        HostPopup.dismissAll()

        dismiss(animated: true) {
            if let next = next {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard let root = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                        .first else { return }
                    let runner = MiniAppRunnerController(app: next)
                    runner.modalPresentationStyle = .fullScreen
                    root.present(runner, animated: true)
                }
            }
        }
    }
}
