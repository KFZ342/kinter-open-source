import UIKit

/// 设置界面：启动方式、安装确认、警告提示。
final class SettingsViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var launchMode: LaunchMode = AppSettings.shared.launchMode

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        view.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 4 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1              // 账号
        case 1: return LaunchMode.allCases.count
        case 2: return 2              // 安装选项
        default: return 1             // 关于
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "账号"
        case 1: return "启动方式"
        case 2: return "安装选项"
        default: return "关于"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .none
        switch indexPath.section {
        case 0:
            cell.textLabel?.text = "账号"
            cell.textLabel?.textColor = .label
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
            // 右侧显示登录状态
            let statusLabel = UILabel()
            statusLabel.font = .systemFont(ofSize: 14)
            if let user = KinterAuthManager.shared.restoreSession() {
                statusLabel.text = user.displayName
                statusLabel.textColor = .secondaryLabel
            } else {
                statusLabel.text = "未登录"
                statusLabel.textColor = .tertiaryLabel
            }
            statusLabel.sizeToFit()
            cell.accessoryView = statusLabel
            return cell

        case 1:
            let mode = LaunchMode.allCases[indexPath.row]
            cell.textLabel?.text = mode.displayName
            cell.accessoryView = nil
            cell.detailTextLabel?.text = nil
            if mode == launchMode {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            // custom 模式下显示选中的应用名
            if mode == .custom, let id = AppSettings.shared.customAppId,
               let app = AppLibrary.shared.app(id: id) {
                cell.accessoryView = makeSubtitleLabel(app.name)
            }
        case 2:
            if indexPath.row == 0 {
                cell.textLabel?.text = "安装前确认"
                let sw = UISwitch()
                sw.isOn = AppSettings.shared.confirmInstall
                sw.addTarget(self, action: #selector(toggleConfirm(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else {
                cell.textLabel?.text = "显示安装警告"
                let sw = UISwitch()
                sw.isOn = AppSettings.shared.showWarnings
                sw.addTarget(self, action: #selector(toggleWarnings(_:)), for: .valueChanged)
                cell.accessoryView = sw
            }
        default:
            cell.textLabel?.text = "Kinter v1.2"
            cell.textLabel?.textColor = .secondaryLabel
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            navigationController?.pushViewController(AccountViewController(), animated: true)
            return
        }
        if indexPath.section == 1 {
            let mode = LaunchMode.allCases[indexPath.row]
            if mode == .custom {
                // 弹出配置页
                let vc = CustomLaunchConfigViewController()
                let nav = UINavigationController(rootViewController: vc)
                nav.modalPresentationStyle = .formSheet
                present(nav, animated: true)
                return
            }
            launchMode = mode
            AppSettings.shared.launchMode = mode
            tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
        }
    }

    /// 右侧显示的小号应用名标签
    private func makeSubtitleLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 14)
        l.textColor = .secondaryLabel
        l.sizeToFit()
        return l
    }

    @objc private func toggleConfirm(_ sw: UISwitch) { AppSettings.shared.confirmInstall = sw.isOn }
    @objc private func toggleWarnings(_ sw: UISwitch) { AppSettings.shared.showWarnings = sw.isOn }
}
