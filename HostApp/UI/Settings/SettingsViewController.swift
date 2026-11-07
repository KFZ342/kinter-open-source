import UIKit

/// 设置界面：账号、安全模式、关于。
final class SettingsViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)

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
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1              // 账号
        case 1: return 2              // 安全模式：开关 + 隐私记录入口
        default: return 1             // 关于
        }
    }

    /// 版本号从 Info.plist 读，不再手写——手写过一次 "v1.2"，和实际包永远对不上
    private static var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v)（build \(b)）"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        let all = CapabilityRegistry.shared.allCapabilities()
        guard !all.isEmpty else { return nil }
        let covered = all.keys.filter {
            SecurityPolicy.tier(of: $0) != nil || SecurityPolicy.isHardDenied($0)
        }.count
        return "已分级 \(covered) / \(all.count) 项能力。低敏能力只记录、不打扰。"
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "账号"
        case 1: return "安全模式"
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
            if indexPath.row == 0 {
                cell.textLabel?.text = "开启安全模式"
                cell.textLabel?.textColor = .label
                cell.accessoryView = nil
                let sw = UISwitch()
                sw.isOn = SecurityMode.shared.isEnabled
                sw.addTarget(self, action: #selector(toggleSecurityMode(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else {
                cell.textLabel?.text = "App 隐私记录"
                cell.textLabel?.textColor = .label
                cell.accessoryView = nil
                cell.accessoryType = .disclosureIndicator
            }

        default:
            cell.textLabel?.text = "Kinter \(Self.versionText)"
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
        if indexPath.section == 1, indexPath.row == 1 {
            navigationController?.pushViewController(PrivacyReportViewController(), animated: true)
        }
    }

    @objc private func toggleSecurityMode(_ sw: UISwitch) {
        SecurityMode.shared.isEnabled = sw.isOn
        HostPopup.toast(sw.isOn ? "安全模式已开启：敏感能力将被拦截" : "安全模式已关闭")
    }
}
