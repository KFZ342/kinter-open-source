import UIKit

/// 账号页：Kinter 账号登录状态。
final class AccountViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var state: AuthState = .loggedOut
    private var isLoggingIn = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "账号"
        view.backgroundColor = .systemGroupedBackground

        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.register(AvatarCell.self, forCellReuseIdentifier: AvatarCell.reuseID)
        table.register(AuthServerFieldCell.self, forCellReuseIdentifier: AuthServerFieldCell.reuseID)
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshState()

        KinterAuthManager.shared.validate { [weak self] ok in
            if !ok { self?.refreshState() }
        }
    }

    private func refreshState() {
        if let user = KinterAuthManager.shared.restoreSession() {
            state = .loggedIn(user)
        } else {
            state = .loggedOut
        }
        table.reloadData()
    }

    private func showLoginSheet(isRegister: Bool) {
        guard !isLoggingIn else { return }
        let title = isRegister ? "注册账号" : "登录"
        let alert = UIAlertController(title: title,
                                      message: isRegister ? "用户名 4-32 位，密码至少 8 位" : nil,
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "用户名"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.keyboardType = .asciiCapable
        }
        alert.addTextField { tf in
            tf.placeholder = "密码"
            tf.isSecureTextEntry = true
        }
        if isRegister {
            alert.addTextField { tf in
                tf.placeholder = "昵称（可选）"
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: isRegister ? "注册" : "登录", style: .default) { [weak self] _ in
            let username = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces) ?? ""
            let password = alert.textFields?[1].text ?? ""
            let name = isRegister ? (alert.textFields?[2].text ?? "") : ""
            guard !username.isEmpty, !password.isEmpty else {
                HostPopup.toast("用户名和密码不能为空")
                return
            }
            if isRegister {
                self?.doRegister(username: username, password: password, name: name)
            } else {
                self?.doLogin(username: username, password: password)
            }
        })
        present(alert, animated: true)
    }

    private func doLogin(username: String, password: String) {
        isLoggingIn = true
        table.reloadData()
        KinterAuthManager.shared.login(username: username, password: password) { [weak self] result in
            guard let self = self else { return }
            self.isLoggingIn = false
            switch result {
            case .success(let user):
                self.state = .loggedIn(user)
                self.table.reloadData()
                HostPopup.toast("欢迎，\(user.displayName)")
                NotificationCenter.default.post(name: .authStateDidChange, object: nil)
            case .failure(let err):
                self.table.reloadData()
                HostPopup.modal(title: "登录失败",
                                content: err.localizedDescription,
                                confirmText: "知道了", cancelText: nil) { _ in }
            }
        }
    }

    private func doRegister(username: String, password: String, name: String) {
        isLoggingIn = true
        table.reloadData()
        let displayName = name.isEmpty ? username : name
        KinterAuthManager.shared.register(username: username, password: password, name: displayName) { [weak self] result in
            guard let self = self else { return }
            self.isLoggingIn = false
            switch result {
            case .success(let user):
                self.state = .loggedIn(user)
                self.table.reloadData()
                HostPopup.toast("注册成功，已登录")
                NotificationCenter.default.post(name: .authStateDidChange, object: nil)
            case .failure(let err):
                self.table.reloadData()
                HostPopup.modal(title: "注册失败",
                                content: err.localizedDescription,
                                confirmText: "知道了", cancelText: nil) { _ in }
            }
        }
    }

    private func confirmLogout() {
        let alert = UIAlertController(title: "退出登录",
                                      message: "退出后不会删除已安装的应用",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
            KinterAuthManager.shared.logout()
            self?.refreshState()
            HostPopup.toast("已退出")
            NotificationCenter.default.post(name: .authStateDidChange, object: nil)
        })
        present(alert, animated: true)
    }
}


extension AccountViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return state.isLoggedIn ? 1 : 2
        default: return 1          // 服务器
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "状态"
        case 1: return "操作"
        default: return "服务器"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 && !state.isLoggedIn {
            return "登录后，小程序可通过 wx.getAccount() 读取你的公开资料。"
        }
        if section == 2 {
            return "账号/商店/付费服务地址。本地测试可填 serveo/localhost.run 隧道地址。"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: AvatarCell.reuseID, for: indexPath) as! AvatarCell
            switch state {
            case .loggedOut:
                cell.configure(user: nil, subtitle: isLoggingIn ? "处理中…" : "未登录")
            case .loggedIn(let user):
                cell.configure(user: user, subtitle: "@\(user.username)")
            }
            cell.selectionStyle = .none
            return cell
        }

        // 服务器地址输入
        if indexPath.section == 2 {
            let cell = tableView.dequeueReusableCell(withIdentifier: AuthServerFieldCell.reuseID, for: indexPath) as! AuthServerFieldCell
            cell.configure(value: AppSettings.shared.authServerURL ?? "") { [weak self] text in
                AppSettings.shared.authServerURL = text.trimmingCharacters(in: .whitespaces)
                self?.table.reloadData()
            }
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.textLabel?.textAlignment = .center

        if isLoggingIn {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.textLabel?.text = "请稍候…"
            cell.textLabel?.textColor = .secondaryLabel
            cell.accessoryView = spinner
            return cell
        }

        if state.isLoggedIn {
            cell.textLabel?.text = "退出登录"
            cell.textLabel?.textColor = .systemRed
        } else {
            if indexPath.row == 0 {
                cell.textLabel?.text = "登录"
                cell.textLabel?.textColor = .systemBlue
            } else {
                cell.textLabel?.text = "注册新账号"
                cell.textLabel?.textColor = .systemGreen
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1, !isLoggingIn else { return }
        if state.isLoggedIn {
            confirmLogout()
        } else {
            showLoginSheet(isRegister: indexPath.row == 1)
        }
    }
}

/// 头像 + 名称单元格。
final class AvatarCell: UITableViewCell {
    static let reuseID = "AvatarCell"

    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 22
        avatarView.backgroundColor = .tertiarySystemFill
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(avatarView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            stack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(user: KinterUser?, subtitle: String) {
        if let user = user {
            nameLabel.text = user.displayName
            subtitleLabel.text = subtitle
            let initial = String(user.displayName.prefix(1)).uppercased()
            avatarView.image = makeInitialAvatar(initial)
        } else {
            nameLabel.text = "未登录"
            subtitleLabel.text = subtitle
            avatarView.image = UIImage(systemName: "person.crop.circle")
            avatarView.tintColor = .tertiaryLabel
        }
    }

    private func makeInitialAvatar(_ text: String) -> UIImage? {
        let size = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.systemBlue.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let s = text as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: (size.width - sz.width) / 2,
                               y: (size.height - sz.height) / 2),
                   withAttributes: attrs)
        }
    }
}

// MARK: - 通知

extension Notification.Name {
    static let authStateDidChange = Notification.Name("AuthStateDidChange")
}

/// 认证服务器地址输入单元格。
final class AuthServerFieldCell: UITableViewCell, UITextFieldDelegate {
    static let reuseID = "AuthServerFieldCell"

    private let field = UITextField()
    private var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 12)
        field.placeholder = "https://..."
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.delegate = self
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        contentView.addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(value: String, onChange: @escaping (String) -> Void) {
        field.text = value
        self.onChange = onChange
    }

    @objc private func editingChanged() {
        onChange?(field.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
