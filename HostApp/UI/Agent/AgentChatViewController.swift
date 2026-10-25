import UIKit

/// AI Agent 聊天界面：对话式生成/管理小程序。
/// 进入方式：AI 页（新会话）或应用详情“AI 修改”（绑定已装小程序迭代）。
final class AgentChatViewController: UIViewController {

    private let runtime: AgentRuntime
    private let table = UITableView(frame: .zero, style: .plain)
    private let inputField = UITextField()
    private let sendBtn = UIButton(type: .system)
    private let stopBtn = UIButton(type: .system)
    private let inputBar = UIView()
    /// 流式输出节流刷新计时器（防止高频 reloadData 卡死主线程）
    private var streamRefreshTimer: Timer?

    init(boundApp: InstalledApp? = nil) {
        runtime = AgentRuntime(boundApp: boundApp)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let isIterate = runtime.boundApp != nil
        title = isIterate ? "AI 修改" : "AI 助手"
        view.backgroundColor = .systemGroupedBackground

        // 消息列表
        table.dataSource = self
        table.delegate = self
        table.register(AgentBubbleCell.self, forCellReuseIdentifier: AgentBubbleCell.reuseID)
        table.separatorStyle = .none
        table.keyboardDismissMode = .interactive
        table.estimatedRowHeight = 60
        table.rowHeight = UITableView.automaticDimension
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        // 输入栏
        inputBar.backgroundColor = .secondarySystemGroupedBackground
        inputBar.layer.cornerRadius = 20
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        inputField.placeholder = isIterate ? "告诉 AI 怎么改…" : "描述你想要的小程序…"
        inputField.font = .systemFont(ofSize: 15)
        inputField.returnKeyType = .send
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.delegate = self
        inputBar.addSubview(inputField)

        sendBtn.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        sendBtn.tintColor = .systemBlue
        sendBtn.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendBtn.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(sendBtn)

        stopBtn.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
        stopBtn.tintColor = .systemRed
        stopBtn.isHidden = true
        stopBtn.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        stopBtn.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(stopBtn)

        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            inputBar.heightAnchor.constraint(equalToConstant: 48),

            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 14),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            inputField.trailingAnchor.constraint(equalTo: sendBtn.leadingAnchor, constant: -8),

            sendBtn.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendBtn.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendBtn.widthAnchor.constraint(equalToConstant: 34),
            sendBtn.heightAnchor.constraint(equalToConstant: 34),

            stopBtn.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            stopBtn.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            stopBtn.widthAnchor.constraint(equalToConstant: 34),
            stopBtn.heightAnchor.constraint(equalToConstant: 34)
        ])

        // 运行时回调（流式输出时节流刷新，防止 AI 长代码输出把主线程刷死）
        runtime.onUpdate = { [weak self] in
            guard let self = self else { return }
            let streaming = self.runtime.messages.contains { $0.isStreaming }
            if streaming {
                if self.streamRefreshTimer == nil {
                    self.refreshTable()   // 流式第一帧立即刷
                    let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
                        self?.refreshTable()
                    }
                    timer.tolerance = 0.03
                    RunLoop.main.add(timer, forMode: .common)
                    self.streamRefreshTimer = timer
                }
            } else {
                self.streamRefreshTimer?.invalidate()
                self.streamRefreshTimer = nil
                self.refreshTable()
            }
        }
        runtime.onOpenApp = { [weak self] app in
            guard let self = self else { return }
            MiniAppLauncher.open(app: app, from: self)
        }
        runtime.onPresent = { [weak self] vc in
            guard let self = self else { return }
            if let popover = vc.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            }
            self.present(vc, animated: true)
        }

        // 键盘监听（聊天气泡不被遮挡）
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
    }

    deinit {
        streamRefreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 动作

    @objc private func sendTapped() {
        guard let text = inputField.text, !text.isEmpty else { return }
        inputField.text = ""
        runtime.send(text)
    }

    @objc private func stopTapped() {
        runtime.cancel()
    }

    private func refreshTable() {
        guard viewIfLoaded?.window != nil else { return }
        table.reloadData()
        scrollToBottom(animated: false)
        sendBtn.isHidden = runtime.isBusy
        stopBtn.isHidden = !runtime.isBusy
    }

    private func scrollToBottom(animated: Bool = true) {
        let count = runtime.messages.count
        guard count > 0 else { return }
        let idx = IndexPath(row: count - 1, section: 0)
        if table.numberOfRows(inSection: 0) > idx.row {
            table.scrollToRow(at: idx, at: .bottom, animated: animated)
        }
    }

    @objc private func keyboardWillShow(_ n: Notification) {
        guard let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let dy = frame.height - view.safeAreaInsets.bottom
        view.transform = .identity
        view.transform = CGAffineTransform(translationX: 0, y: -dy)
    }

    @objc private func keyboardWillHide(_ n: Notification) {
        view.transform = .identity
    }
}

// MARK: - 消息列表

extension AgentChatViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        runtime.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AgentBubbleCell.reuseID, for: indexPath) as! AgentBubbleCell
        cell.onCardTap = { [weak self] card in
            self?.showCardDetail(card)
        }
        cell.configure(message: runtime.messages[indexPath.row])
        return cell
    }

    /// 点击卡片 → 详情页（Markdown 渲染）
    private func showCardDetail(_ card: AgentRuntime.AgentCard) {
        let vc = AgentCardDetailViewController(card: card)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
}

// MARK: - 输入框

extension AgentChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return true
    }
}

// MARK: - 消息气泡

final class AgentBubbleCell: UITableViewCell {
    static let reuseID = "AgentBubbleCell"

    private let bubble = UIView()
    private let label = UILabel()
    private let cardView = AgentCardView()
    private var leftAnchorCon: NSLayoutConstraint!
    private var rightAnchorCon: NSLayoutConstraint!
    private var minLeftCon: NSLayoutConstraint!
    private var maxRightCon: NSLayoutConstraint!
    /// 卡片点击回调
    var onCardTap: ((AgentRuntime.AgentCard) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.isHidden = true
        bubble.addSubview(cardView)

        bubble.layer.cornerRadius = 14
        bubble.layer.cornerCurve = .continuous
        bubble.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)

        leftAnchorCon = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        rightAnchorCon = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        minLeftCon = bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 40)
        maxRightCon = bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.88),

            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),

            cardView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            cardView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)
        ])

        cardView.onTap = { [weak self] in
            guard let card = self?.currentCard else { return }
            self?.onCardTap?(card)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var currentCard: AgentRuntime.AgentCard?

    func configure(message: AgentRuntime.ChatMessage) {
        currentCard = message.card
        if let card = message.card {
            label.isHidden = true
            cardView.isHidden = false
            cardView.configure(card: card)
        } else {
            cardView.isHidden = true
            label.isHidden = false
            if message.isStreaming {
                // 流式输出中：纯文本渲染（Markdown 解析开销大，等输出完再做）
                label.attributedText = nil
                label.text = message.text + "▋"
            } else {
                label.text = nil
                label.attributedText = message.text.markdownRendered
            }
        }
        if message.role == "user" {
            bubble.backgroundColor = .systemBlue
            label.textColor = .white
            rightAnchorCon.isActive = true
            minLeftCon.isActive = true
            leftAnchorCon.isActive = false
            maxRightCon.isActive = false
        } else {
            bubble.backgroundColor = .secondarySystemGroupedBackground
            label.textColor = .label
            leftAnchorCon.isActive = true
            maxRightCon.isActive = true
            rightAnchorCon.isActive = false
            minLeftCon.isActive = false
        }
    }
}

/// 工具执行结果卡片（点击查看详情）
final class AgentCardView: UIView {
    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let detailHint = UILabel()
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        iconLabel.font = .systemFont(ofSize: 30)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconLabel)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        summaryLabel.font = .systemFont(ofSize: 13)
        summaryLabel.textColor = .label
        summaryLabel.numberOfLines = 3
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(summaryLabel)

        detailHint.text = "点击查看详细信息  ›"
        detailHint.font = .systemFont(ofSize: 12, weight: .medium)
        detailHint.textColor = .systemBlue
        detailHint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailHint)

        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconLabel.widthAnchor.constraint(equalToConstant: 36),
            iconLabel.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            subtitleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 10),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            summaryLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 8),

            detailHint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            detailHint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            detailHint.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            detailHint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(card: AgentRuntime.AgentCard) {
        switch card.type {
        case "generate", "iterate": iconLabel.text = "🛠"
        case "install":             iconLabel.text = "📦"
        case "publish":             iconLabel.text = "🚀"
        case "list":                iconLabel.text = "📱"
        case "delete":              iconLabel.text = "🗑"
        default:                    iconLabel.text = "🤖"
        }
        titleLabel.text = card.title
        subtitleLabel.text = card.subtitle
        summaryLabel.text = card.summary
    }

    @objc private func tapped() { onTap?() }
}

/// 卡片详情页（Markdown 渲染）
final class AgentCardDetailViewController: UIViewController {
    private let card: AgentRuntime.AgentCard
    private let textView = UITextView()

    init(card: AgentRuntime.AgentCard) {
        self.card = card
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = card.type == "list" ? "我的小程序" : card.title
        view.backgroundColor = .systemBackground

        let closeBtn = UIBarButtonItem(barButtonSystemItem: .close, target: self,
                                       action: #selector(closeTapped))
        let copyBtn = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"),
                                      style: .plain, target: self,
                                      action: #selector(copyTapped))
        navigationItem.leftBarButtonItem = closeBtn
        navigationItem.rightBarButtonItem = copyBtn

        textView.isEditable = false
        textView.font = .systemFont(ofSize: 15)
        textView.contentInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
        textView.textContainerInset = .zero
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        textView.attributedText = card.detail.markdownRendered
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func copyTapped() {
        UIPasteboard.general.string = card.detail
        let alert = UIAlertController(title: "已复制", message: "详细信息已复制到剪贴板", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

/// 二维码预览页
final class QRPreviewViewController: UIViewController {
    private let qrImage: UIImage
    private let content: String

    init(qrImage: UIImage, content: String) {
        self.qrImage = qrImage
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let closeBtn = UIBarButtonItem(barButtonSystemItem: .close, target: self,
                                       action: #selector(closeTapped))
        let copyBtn = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"),
                                      style: .plain, target: self,
                                      action: #selector(copyTapped))
        navigationItem.leftBarButtonItem = closeBtn
        navigationItem.rightBarButtonItem = copyBtn

        let imageView = UIImageView(image: qrImage)
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 16
        imageView.layer.cornerCurve = .continuous
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        let hint = UILabel()
        hint.text = "用手机相机扫一扫即可打开内容"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabel
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        let contentLabel = UILabel()
        contentLabel.text = content
        contentLabel.font = .systemFont(ofSize: 14)
        contentLabel.textColor = .label
        contentLabel.textAlignment = .center
        contentLabel.numberOfLines = 0
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentLabel)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            imageView.widthAnchor.constraint(equalToConstant: 300),
            imageView.heightAnchor.constraint(equalToConstant: 300),

            hint.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            contentLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            contentLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func copyTapped() {
        UIPasteboard.general.string = content
        let alert = UIAlertController(title: "已复制", message: "二维码内容已复制到剪贴板", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Markdown 渲染（完整块级解析 + 表格等宽对齐渲染，失败回退纯文本）

extension String {
    /// 用系统 Markdown 解析渲染为 NSAttributedString。
    /// 支持标题/列表/引用/代码块/行内样式；Markdown 表格（GitHub 语法）单独等宽对齐渲染。
    var markdownRendered: NSAttributedString {
        StringRenderer.markdown(self)
    }
}

enum StringRenderer {
    /// 完整 Markdown 渲染（含表格支持）
    static func markdown(_ text: String) -> NSAttributedString {
        let lines = text.components(separatedBy: "\n")
        let out = NSMutableAttributedString()
        var plain = ""

        func flushPlain() {
            if plain.isEmpty { return }
            if let md = try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .full)) {
                out.append(NSAttributedString(md))
            } else {
                out.append(NSAttributedString(string: plain, attributes: [.font: UIFont.systemFont(ofSize: 15)]))
            }
            plain = ""
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.contains("|"), i + 1 < lines.count,
               isSeparatorRow(lines[i + 1]) {
                // 表格块：收集连续含 | 行
                var block: [String] = []
                var j = i
                while j < lines.count && lines[j].contains("|") {
                    block.append(lines[j])
                    j += 1
                }
                flushPlain()
                out.append(renderTable(block))
                out.append(NSAttributedString(string: "\n"))
                i = j
                continue
            }
            plain += line + "\n"
            i += 1
        }
        flushPlain()
        return out
    }

    /// 判断是否为表格分隔行（|---|:---:|---|）
    private static func isSeparatorRow(_ line: String) -> Bool {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        let cells = t.split(separator: "|")
        return !cells.isEmpty && cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    /// 表格块 → 等宽字体对齐渲染（表头加粗 + 分隔线）
    private static func renderTable(_ block: [String]) -> NSAttributedString {
        var parsed: [[String]] = []
        for line in block {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            parsed.append(t.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        guard let sepIdx = parsed.firstIndex(where: { rows in
            !rows.isEmpty && rows.allSatisfy { $0.allSatisfy { $0 == "-" || $0 == ":" } }
        }), sepIdx > 0 else {
            return NSAttributedString(string: block.joined(separator: "\n"),
                                      attributes: [.font: UIFont.systemFont(ofSize: 15)])
        }

        let header = parsed[sepIdx - 1]
        var dataRows: [[String]] = []
        for (idx, row) in parsed.enumerated() where idx != sepIdx && idx != sepIdx - 1 {
            dataRows.append(row)
        }
        let colCount = max(header.count, dataRows.map(\.count).max() ?? 0)
        var colWidths = Array(repeating: 0, count: colCount)
        for (idx, cell) in header.enumerated() where idx < colCount { colWidths[idx] = max(colWidths[idx], cell.count) }
        for row in dataRows {
            for (idx, cell) in row.enumerated() where idx < colCount { colWidths[idx] = max(colWidths[idx], cell.count) }
        }

        func pad(_ cell: String, _ width: Int) -> String {
            cell + String(repeating: " ", count: max(0, width - cell.count))
        }
        func makeLine(_ row: [String]) -> String {
            (0..<colCount).map { idx in
                pad(idx < row.count ? row[idx] : "", colWidths[idx])
            }.joined(separator: "  ")
        }

        let tableFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let headerFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 3

        let attrs: [NSAttributedString.Key: Any] = [.font: tableFont, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
        let headAttrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: makeLine(header), attributes: headAttrs))
        out.append(NSAttributedString(string: "\n", attributes: headAttrs))
        out.append(NSAttributedString(string: colWidths.map { String(repeating: "-", count: $0) }.joined(separator: "  "), attributes: attrs))
        for row in dataRows {
            out.append(NSAttributedString(string: "\n" + makeLine(row), attributes: attrs))
        }
        return out
    }
}
