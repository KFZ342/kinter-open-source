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

        // 运行时回调
        runtime.onUpdate = { [weak self] in
            guard let self = self else { return }
            self.table.reloadData()
            self.scrollToBottom()
            self.sendBtn.isHidden = self.runtime.isBusy
            self.stopBtn.isHidden = !self.runtime.isBusy
        }
        runtime.onOpenApp = { [weak self] app in
            guard let self = self else { return }
            MiniAppLauncher.open(app: app, from: self)
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
        cell.configure(message: runtime.messages[indexPath.row])
        return cell
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
    private var leftAnchorCon: NSLayoutConstraint!
    private var rightAnchorCon: NSLayoutConstraint!
    private var minLeftCon: NSLayoutConstraint!
    private var maxRightCon: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

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
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),

            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(message: AgentRuntime.ChatMessage) {
        label.text = message.text + (message.isStreaming ? "▋" : "")
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
