import UIKit

/// AI 生成小程序页。
final class AIGenerateViewController: UIViewController {

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let descField = UITextView()
    private let placeholderLabel = UILabel()
    private let generateBtn = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let resultCard = UIView()
    private let resultLabel = UILabel()
    private let installBtn = UIButton(type: .system)
    private let publishBtn = UIButton(type: .system)
    private let discardBtn = UIButton(type: .system)
    private let sourceLabel = UILabel()
    private let priceField = UITextField()
    private let priceRow = UIStackView()

    private var generated: AIGenerator.GeneratedApp?
    private var generatedDir: URL?

    /// 迭代模式：预填描述、导入时覆盖原应用
    private let iterateApp: InstalledApp?

    init(iterateApp: InstalledApp? = nil) {
        self.iterateApp = iterateApp
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }
    private var startTime: Date?
    private var timer: Timer?

    // 实时预览
    private let previewCard = UIView()
    private let previewHeader = UILabel()
    private let thinkingLabel = UILabel()
    private let previewText = UITextView()
    private let cancelBtn = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = iterateApp != nil ? "迭代生成" : "AI 生成"
        view.backgroundColor = .systemGroupedBackground
        setupUI()
        if let prev = iterateApp?.generationPrompt, !prev.isEmpty {
            descField.text = prev
            placeholderLabel.isHidden = true
        }
    }

    private func setupUI() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 40, trailing: 20)
        scroll.addSubview(content)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])

        // 标题
        let title = UILabel()
        title.text = "描述你想要的小程序"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        content.addArrangedSubview(title)

        let hint = UILabel()
        hint.text = "模型会根据描述生成完整的 HTML + manifest。生成后可直接导入应用库。"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        content.addArrangedSubview(hint)

        // 描述输入
        let descCard = UIView()
        descCard.backgroundColor = .secondarySystemGroupedBackground
        descCard.layer.cornerRadius = 12
        descCard.translatesAutoresizingMaskIntoConstraints = false

        descField.translatesAutoresizingMaskIntoConstraints = false
        descField.font = .systemFont(ofSize: 15)
        descField.backgroundColor = .clear
        descField.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        descField.isScrollEnabled = false
        descCard.addSubview(descField)

        placeholderLabel.text = "例如：帮我做一个记账应用，可以添加收支记录，按月份统计，支持删除"
        placeholderLabel.font = .systemFont(ofSize: 15)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        descCard.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            descField.topAnchor.constraint(equalTo: descCard.topAnchor),
            descField.leadingAnchor.constraint(equalTo: descCard.leadingAnchor),
            descField.trailingAnchor.constraint(equalTo: descCard.trailingAnchor),
            descField.bottomAnchor.constraint(equalTo: descCard.bottomAnchor),
            descField.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            placeholderLabel.topAnchor.constraint(equalTo: descCard.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: descCard.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(equalTo: descCard.trailingAnchor, constant: -16)
        ])

        descField.delegate = self
        content.addArrangedSubview(descCard)

        // 生成按钮
        generateBtn.setTitle("生成", for: .normal)
        generateBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        generateBtn.backgroundColor = .systemBlue
        generateBtn.setTitleColor(.white, for: .normal)
        generateBtn.layer.cornerRadius = 12
        generateBtn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        generateBtn.addTarget(self, action: #selector(startGenerate), for: .touchUpInside)
        content.addArrangedSubview(generateBtn)

        // 状态
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        content.addArrangedSubview(statusLabel)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(spinner)

        // 结果卡片
        resultCard.backgroundColor = .secondarySystemGroupedBackground
        resultCard.layer.cornerRadius = 12
        resultCard.isHidden = true
        resultCard.translatesAutoresizingMaskIntoConstraints = false

        resultLabel.font = .systemFont(ofSize: 14)
        resultLabel.numberOfLines = 0
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultCard.addSubview(resultLabel)

        let buttons = UIStackView()
        buttons.axis = .vertical
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        buttons.translatesAutoresizingMaskIntoConstraints = false
        resultCard.addSubview(buttons)

        // 价格输入行（发布付费小程序用；0 = 免费）
        let priceLabel = UILabel()
        priceLabel.text = "售价(元)"
        priceLabel.font = .systemFont(ofSize: 14, weight: .medium)
        priceField.placeholder = "0 = 免费"
        priceField.keyboardType = .decimalPad
        priceField.text = "0"
        priceField.textAlignment = .right
        priceField.font = .systemFont(ofSize: 14)
        priceField.borderStyle = .roundedRect
        priceRow.axis = .horizontal
        priceRow.spacing = 10
        priceRow.distribution = .fillProportionally
        priceRow.translatesAutoresizingMaskIntoConstraints = false
        priceRow.addArrangedSubview(priceLabel)
        priceRow.addArrangedSubview(priceField)
        priceRow.isHidden = true
        priceField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        resultCard.addSubview(priceRow)

        // 发布按钮（安装后显示）
        publishBtn.setTitle("发布到我的商店", for: .normal)
        publishBtn.setTitleColor(.white, for: .normal)
        publishBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        publishBtn.backgroundColor = .systemBlue
        publishBtn.layer.cornerRadius = 10
        publishBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        publishBtn.isHidden = true
        publishBtn.addTarget(self, action: #selector(publishResult), for: .touchUpInside)
        buttons.addArrangedSubview(publishBtn)

        discardBtn.setTitle("放弃", for: .normal)
        discardBtn.setTitleColor(.systemRed, for: .normal)
        discardBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        discardBtn.backgroundColor = .tertiarySystemGroupedBackground
        discardBtn.layer.cornerRadius = 10
        discardBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        discardBtn.addTarget(self, action: #selector(discardResult), for: .touchUpInside)
        buttons.addArrangedSubview(discardBtn)

        installBtn.setTitle("导入应用库", for: .normal)
        installBtn.setTitleColor(.white, for: .normal)
        installBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        installBtn.backgroundColor = .systemGreen
        installBtn.layer.cornerRadius = 10
        installBtn.addTarget(self, action: #selector(installResult), for: .touchUpInside)
        buttons.addArrangedSubview(installBtn)

        sourceLabel.font = .systemFont(ofSize: 12)
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.numberOfLines = 0
        sourceLabel.isHidden = true
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        resultCard.addSubview(sourceLabel)

        NSLayoutConstraint.activate([
            resultLabel.topAnchor.constraint(equalTo: resultCard.topAnchor, constant: 16),
            resultLabel.leadingAnchor.constraint(equalTo: resultCard.leadingAnchor, constant: 16),
            resultLabel.trailingAnchor.constraint(equalTo: resultCard.trailingAnchor, constant: -16),

            priceRow.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 12),
            priceRow.leadingAnchor.constraint(equalTo: resultCard.leadingAnchor, constant: 16),
            priceRow.trailingAnchor.constraint(equalTo: resultCard.trailingAnchor, constant: -16),

            sourceLabel.topAnchor.constraint(equalTo: priceRow.bottomAnchor, constant: 12),
            sourceLabel.leadingAnchor.constraint(equalTo: resultCard.leadingAnchor, constant: 16),
            sourceLabel.trailingAnchor.constraint(equalTo: resultCard.trailingAnchor, constant: -16),

            buttons.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 12),
            buttons.leadingAnchor.constraint(equalTo: resultCard.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: resultCard.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: resultCard.bottomAnchor, constant: -16)
        ])

        // 实时预览卡片
        previewCard.backgroundColor = .secondarySystemGroupedBackground
        previewCard.layer.cornerRadius = 12
        previewCard.isHidden = true
        previewCard.translatesAutoresizingMaskIntoConstraints = false

        previewHeader.font = .systemFont(ofSize: 12, weight: .semibold)
        previewHeader.textColor = .secondaryLabel
        previewHeader.text = "实时输出"
        previewHeader.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(previewHeader)

        thinkingLabel.font = .systemFont(ofSize: 11)
        thinkingLabel.textColor = .tertiaryLabel
        thinkingLabel.numberOfLines = 2
        thinkingLabel.lineBreakMode = .byTruncatingTail
        thinkingLabel.isHidden = true
        thinkingLabel.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(thinkingLabel)

        previewText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        previewText.backgroundColor = .tertiarySystemGroupedBackground
        previewText.layer.cornerRadius = 8
        previewText.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        previewText.isEditable = false
        previewText.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(previewText)

        cancelBtn.setTitle("取消生成", for: .normal)
        cancelBtn.setTitleColor(.systemRed, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        cancelBtn.addTarget(self, action: #selector(cancelGenerate), for: .touchUpInside)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            previewHeader.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 12),
            previewHeader.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 14),
            previewHeader.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -14),

            thinkingLabel.topAnchor.constraint(equalTo: previewHeader.bottomAnchor, constant: 4),
            thinkingLabel.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 14),
            thinkingLabel.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -14),

            previewText.topAnchor.constraint(equalTo: thinkingLabel.bottomAnchor, constant: 8),
            previewText.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            previewText.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
            previewText.heightAnchor.constraint(equalToConstant: 220),

            cancelBtn.topAnchor.constraint(equalTo: previewText.bottomAnchor, constant: 8),
            cancelBtn.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
            cancelBtn.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -10),
            cancelBtn.widthAnchor.constraint(equalToConstant: 100),
            cancelBtn.heightAnchor.constraint(equalToConstant: 30)
        ])

        content.addArrangedSubview(previewCard)
        content.addArrangedSubview(resultCard)
    }

    private func setLoading(_ loading: Bool, status: String = "") {
        generateBtn.isEnabled = !loading
        generateBtn.alpha = loading ? 0.5 : 1
        statusLabel.isHidden = status.isEmpty
        statusLabel.text = status
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    /// 读取已安装应用的所有文本文件，用于迭代上下文。
    /// 只读文本文件（html/css/js/svg/json/txt），跳过图片和二进制。
    /// 单文件上限 200KB，总上下文上限 1MB，防止 prompt 超限。
    private func loadCurrentFiles(_ app: InstalledApp) -> [String: String] {
        var result: [String: String] = [:]
        var totalSize = 0
        let dir = app.directory
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir,
                                             includingPropertiesForKeys: [.isRegularFileKey]) else {
            return result
        }
        let textExts: Set<String> = ["html", "htm", "css", "js", "svg", "json", "txt", "xml"]
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard textExts.contains(ext) else { continue }
            // 跳过 manifest.json（由系统生成）
            if url.lastPathComponent == "manifest.json" { continue }
            // 限制单文件大小 200KB
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            if let size = attrs?[.size] as? Int, size > 200_000 { continue }
            totalSize += attrs?[.size] as? Int ?? 0
            if totalSize > 1_000_000 { break }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 相对路径
            let rel = url.path.replacingOccurrences(of: dir.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            result[rel] = content
        }
        return result
    }

    @objc private func startGenerate() {
        let desc = descField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard desc.count >= 4 else {
            HostPopup.toast("描述太短，请说清楚要什么")
            return
        }
        guard AISettings.shared.isConfigured else {
            let alert = UIAlertController(title: "未配置模型",
                                          message: "请先在设置 → AI 模型 里填写接口",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
                self.navigationController?.pushViewController(AIModelSettingsViewController(), animated: true)
            })
            present(alert, animated: true)
            return
        }

        descField.resignFirstResponder()
        resultCard.isHidden = true
        previewCard.isHidden = false
        previewText.text = ""
        thinkingLabel.text = ""
        thinkingLabel.isHidden = true
        reasoning = ""
        startTime = Date()
        startTimer()
        setLoading(true, status: "模型连接中…")

        let messages: [AIClient.Message]
        if let prev = iterateApp {
            // 迭代模式：读取现有文件，走迭代提示词
            let files = loadCurrentFiles(prev)
            guard !files.isEmpty else {
                setLoading(false)
                HostPopup.modal(title: "读取失败",
                                content: "无法读取现有应用的文件",
                                confirmText: "知道了", cancelText: nil) { _ in }
                return
            }
            messages = [
                .init(role: "system", content: AIPrompt.iterateSystem),
                .init(role: "user", content: AIPrompt.iterateUser(
                    originalPrompt: prev.generationPrompt ?? "",
                    changeRequest: desc,
                    currentAppId: prev.appId,
                    currentVersion: prev.version,
                    currentFiles: files
                ))
            ]
        } else {
            // 首次生成
            messages = [
                .init(role: "system", content: AIPrompt.system),
                .init(role: "user", content: AIPrompt.user(desc))
            ]
        }

        let client = AIClient()
        self.currentClient = client
        self.accumulated = ""

        client.chatStream(messages: messages, onReasoning: { [weak self] chunk in
            guard let self = self else { return }
            self.reasoning += chunk
            self.thinkingLabel.isHidden = false
            let tail = String(self.reasoning.suffix(120))
            self.thinkingLabel.text = "💭 " + tail
            self.updateProgress()
        }, onDelta: { [weak self] chunk in
            guard let self = self else { return }
            self.accumulated += chunk
            // 节流刷新预览文本（每 50ms 最多一次）
            let now = Date()
            guard now.timeIntervalSince(self.lastPreviewRefresh) >= 0.05 else { return }
            self.lastPreviewRefresh = now
            self.previewText.text = self.accumulated
            // 自动滚动到底
            if self.previewText.contentSize.height > self.previewText.bounds.height {
                let bottom = max(0, self.previewText.contentSize.height - self.previewText.bounds.height)
                self.previewText.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            }
        }, completion: { [weak self] result in
            guard let self = self else { return }
            self.stopTimer()
            switch result {
            case .success(let raw):
                self.handleModelResponse(raw)
            case .failure(let err):
                self.setLoading(false)
                if case AIClient.AIError.cancelled = err {
                    self.statusLabel.text = "已取消"
                } else {
                    HostPopup.modal(title: "生成失败", content: err.localizedDescription,
                                    confirmText: "知道了", cancelText: nil) { _ in }
                }
            }
        })
    }

    // MARK: - 进度与取消

    private var currentClient: AIClient?
    private var accumulated = ""
    private var reasoning = ""
    /// 预览刷新节流：距上次刷新不足 50ms 时跳过，避免流式高频刷新卡 UI
    private var lastPreviewRefresh = Date.distantPast

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateProgress() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        let chars = accumulated.count
        let rchars = reasoning.count
        statusLabel.isHidden = false
        if rchars > 0 {
            statusLabel.text = String(format: "生成中… %.1fs · 思考 %d 字 · 输出 %d 字", elapsed, rchars, chars)
        } else {
            statusLabel.text = String(format: "生成中… %.1fs · %d 字", elapsed, chars)
        }
    }

    @objc private func cancelGenerate() {
        currentClient?.cancel()
        currentClient = nil
        stopTimer()
        setLoading(false)
        statusLabel.text = "已取消"
    }

    private func handleModelResponse(_ raw: String) {
        setLoading(true, status: "解析中…")
        previewCard.isHidden = true
        do {
            let app = try AIGenerator.parse(raw)
            self.generated = app
            setLoading(true, status: "渲染图标中…")
            AIGenerator.writeToDisk(app) { result in
                self.setLoading(false)
                switch result {
                case .success(let dir):
                    self.generatedDir = dir
                    self.showResult(app)
                case .failure(let error):
                    let preview = String(raw.prefix(500))
                    HostPopup.modal(title: "写入失败",
                                    content: "\(error.localizedDescription)\n\n原始返回:\n\(preview)",
                                    confirmText: "知道了", cancelText: nil) { _ in }
                }
            }
        } catch {
            setLoading(false)
            let preview = String(raw.prefix(500))
            HostPopup.modal(title: "解析失败",
                            content: "\(error.localizedDescription)\n\n原始返回:\n\(preview)",
                            confirmText: "知道了", cancelText: nil) { _ in }
        }
    }

    private func showResult(_ app: AIGenerator.GeneratedApp) {
        resultCard.isHidden = false
        let filesDesc = app.files.keys.sorted().map { "  • \($0)" }.joined(separator: "\n")
        let capsDesc = app.capabilities.keys.sorted().map { "  • \($0)" }.joined(separator: "\n")
        let hasIcon = app.files["icon.svg"] != nil
        let iconLine = hasIcon ? "图标：SVG ✓\n" : "图标：无（将显示占位）\n"

        resultLabel.text = """
        \(iconLine)名称：\(app.name)
        ID：\(app.appId)
        分类：\(app.category)
        说明：\(app.description)

        文件：
        \(filesDesc)

        声明能力：
        \(capsDesc.isEmpty ? "  （无）" : capsDesc)
        """
        scroll.setContentOffset(.zero, animated: true)
    }

    @objc private func publishResult() {
        guard let app = generated, let dir = generatedDir else { return }

        // 先确保已安装到应用库
        guard let installed = AppLibrary.shared.app(id: app.appId) else {
            HostPopup.toast("请先导入应用库")
            return
        }

        // 检查登录
        guard KinterAuthManager.shared.restoreSession() != nil else {
            HostPopup.modal(title: "需要登录",
                            content: "发布到商店需要 GitHub 账号。请在设置 → 账号里登录。",
                            confirmText: "去登录",
                            cancelText: "取消") { confirmed in
                if confirmed {
                    self.navigationController?.pushViewController(AccountViewController(), animated: true)
                }
            }
            return
        }

        // 读取售价（元），无效输入按免费处理
        let priceText = priceField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let price = Double(priceText) ?? 0
        if price < 0 {
            HostPopup.toast("价格不能为负数")
            return
        }

        // 按钮变 loading
        publishBtn.isEnabled = false
        publishBtn.setTitle("发布中…", for: .normal)
        publishBtn.alpha = 0.6
        _ = dir

        StorePublisher.shared.publish(app: installed, price: price) { [weak self] result in
            guard let self = self else { return }
            self.publishBtn.isEnabled = true
            self.publishBtn.setTitle("发布到我的商店", for: .normal)
            self.publishBtn.alpha = 1.0

            switch result {
            case .success(let pub):
                self.publishBtn.isHidden = true
                self.priceRow.isHidden = true
                self.sourceLabel.isHidden = false
                self.sourceLabel.text = """
                ✓ 已发布\(pub.price > 0 ? String(format: "（售价 ¥%.2f，平台抽成 7%%）", pub.price) : "（免费）")
                源地址：\(pub.sourceURL)
                """
                // 复制源地址到剪贴板
                UIPasteboard.general.string = pub.sourceURL
                HostPopup.modal(
                    title: "发布成功",
                    content: "源地址已复制到剪贴板。\n\n把它分享给别人，在商店页添加这个源就能安装你的应用。",
                    confirmText: "好",
                    cancelText: nil
                ) { _ in }

            case .failure(let err):
                HostPopup.modal(
                    title: "发布失败",
                    content: err.localizedDescription,
                    confirmText: "知道了",
                    cancelText: nil
                ) { _ in }
            }
        }
    }

    @objc private func discardResult() {
        generated = nil
        if let dir = generatedDir { try? FileManager.default.removeItem(at: dir) }
        generatedDir = nil
        resultCard.isHidden = true
        descField.text = ""
        placeholderLabel.isHidden = false
    }

    @objc private func installResult() {
        guard let app = generated, let dir = generatedDir else { return }

        // 直接安装：用 PackageInstaller 从目录走一次 "文件系统安装"
        // 但 PackageInstaller 需要 zip。这里直接调用一个轻量的安装路径。
        do {
            try installFromDirectory(app: app, sourceDir: dir)
            HostPopup.toast("已导入应用库")
            // 显示发布按钮与价格输入，保留卡片让用户可以继续发布
            installBtn.isHidden = true
            publishBtn.isHidden = false
            priceRow.isHidden = false
        } catch {
            HostPopup.modal(title: "导入失败", content: error.localizedDescription,
                            confirmText: "知道了", cancelText: nil) { _ in }
        }
    }

    /// 从目录直接安装（跳过 ZIP 步骤）
    private func installFromDirectory(app: AIGenerator.GeneratedApp, sourceDir: URL) throws {
        // 构造 InstalledApp 并复制文件
        // 检查是否生成了 icon.png
        let iconPath = sourceDir.appendingPathComponent("icon.png")
        let hasIcon = FileManager.default.fileExists(atPath: iconPath.path)

        let installed = InstalledApp(
            appId: app.appId,
            name: app.name,
            version: app.version,
            installedAt: Date(),
            category: iterateApp?.category ?? app.category,
            disabledCapabilities: [],
            iconFileName: hasIcon ? "icon.png" : nil,
            isAIGenerated: true,
            generationPrompt: descField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let dest = installed.directory
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // 递归复制
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                let rel = fileURL.path.replacingOccurrences(of: sourceDir.path, with: "")
                let target = dest.appendingPathComponent(rel)
                if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    try? fm.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                    try fm.copyItem(at: fileURL, to: target)
                }
            }
        }

        AppLibrary.shared.add(installed)
        installed.ensureDataDirectory()
        NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
    }
}

extension AIGenerateViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}
