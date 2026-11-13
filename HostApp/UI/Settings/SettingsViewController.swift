import UIKit

/// 设置界面：账号、安全模式、开发者签名、关于。
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 信任名单可能在小程序打开时被加过
        table.reloadData()
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 5 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1              // 账号
        case 1: return 2              // 安全模式：开关 + 隐私记录入口
        case 2: return 3              // 开发者签名：要求签名 + 开发模式 + 信任名单
        case 3: return 1              // Web 访问
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
        if section == 2 {
            return "打开应用前重新校验签名与开发者证书。没签名、签名对不上、或证书不是内置根签发的包都会被挡住，提示「未受验证的开发者，App暂时无法打开」。宿主自带和本机 AI 生成的应用不受影响。"
        }
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
        case 2: return "开发者签名"
        case 3: return "互联"
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

        case 2:
            cell.accessoryType = .none
            cell.accessoryView = nil
            if indexPath.row == 0 {
                cell.textLabel?.text = "要求开发者签名"
                cell.textLabel?.textColor = .label
                let sw = UISwitch()
                sw.isOn = AppSettings.shared.requireDeveloperSignature
                sw.addTarget(self, action: #selector(toggleRequireSignature(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "允许自签名（开发模式）"
                cell.textLabel?.textColor = .label
                let sw = UISwitch()
                sw.isOn = AppSettings.shared.allowSelfSignedApps
                sw.addTarget(self, action: #selector(toggleSelfSigned(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else {
                let count = TrustedDevelopers.shared.count
                cell.textLabel?.text = "信任名单"
                cell.textLabel?.textColor = count > 0 ? .label : .secondaryLabel
                let n = UILabel()
                n.font = .systemFont(ofSize: 14)
                n.text = count > 0 ? "\(count) 位开发者" : "空"
                n.textColor = .secondaryLabel
                n.sizeToFit()
                cell.accessoryView = n
                cell.accessoryType = count > 0 ? .disclosureIndicator : .none
            }

        case 3:
            cell.textLabel?.text = "Web 端访问"
            cell.textLabel?.textColor = .label
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
            let statusLabel = UILabel()
            statusLabel.font = .systemFont(ofSize: 14)
            if WebAccessService.shared.isRunning {
                statusLabel.text = "运行中 :\(WebAccessService.shared.runningPort ?? 0)"
                statusLabel.textColor = .secondaryLabel
            } else {
                statusLabel.text = "已关闭"
                statusLabel.textColor = .tertiaryLabel
            }
            statusLabel.sizeToFit()
            cell.accessoryView = statusLabel

        default:
            cell.accessoryView = nil
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
            return
        }
        if indexPath.section == 2, indexPath.row == 2 {
            clearTrustedDevelopers()
            return
        }
        if indexPath.section == 3 {
            navigationController?.pushViewController(WebAccessViewController(), animated: true)
        }
    }

    @objc private func toggleSelfSigned(_ sw: UISwitch) {
        AppSettings.shared.allowSelfSignedApps = sw.isOn
        HostPopup.toast(sw.isOn ? "开发模式：自签名包可以手动信任"
                                : "已关闭：只认根证书签发的应用")
    }

    @objc private func toggleRequireSignature(_ sw: UISwitch) {
        AppSettings.shared.requireDeveloperSignature = sw.isOn
        HostPopup.toast(sw.isOn ? "已要求开发者签名：未签名的应用将无法打开"
                                : "已关闭签名校验：未签名的应用也能打开")
    }

    private func clearTrustedDevelopers() {
        let count = TrustedDevelopers.shared.count
        guard count > 0 else { return }
        let alert = UIAlertController(
            title: "清除信任名单？",
            message: "清除后，这 \(count) 位开发者的应用需要重新确认「信任并打开」。",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            TrustedDevelopers.shared.revokeAll()
            self.table.reloadData()
            HostPopup.toast("信任名单已清空")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    @objc private func toggleSecurityMode(_ sw: UISwitch) {
        SecurityMode.shared.isEnabled = sw.isOn
        HostPopup.toast(sw.isOn ? "安全模式已开启：敏感能力将被拦截" : "安全模式已关闭")
    }
}
