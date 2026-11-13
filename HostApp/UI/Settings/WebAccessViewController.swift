import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Web 访问面板：开关、端口、地址、二维码、访问令牌。
final class WebAccessViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let service = WebAccessService.shared
    private let settings = WebAccessSettings.shared

    private enum Section: Int, CaseIterable {
        case server
        case token
        case guide
    }

    private var running: Bool { service.isRunning }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Web 访问"
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

        service.onStateChange = { [weak self] _, _ in
            DispatchQueue.main.async { self?.table.reloadData() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        table.reloadData()
    }

    // MARK: - 操作

    private func toggleServer(_ on: Bool) {
        if on {
            do {
                try service.start()
                HostPopup.toast("Web 访问已开启")
            } catch {
                HostPopup.toast("开启失败：\(error.localizedDescription)")
                settings.isEnabled = false
            }
        } else {
            service.stop()
            settings.isEnabled = false
            HostPopup.toast("Web 访问已关闭")
        }
        table.reloadData()
    }

    private func promptPort() {
        let alert = UIAlertController(title: "监听端口",
                                      message: "范围 \(WebAccessSettings.portRange.lowerBound)–\(WebAccessSettings.portRange.upperBound)，修改后会重启服务",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.text = String(self.settings.port)
            tf.placeholder = String(WebAccessSettings.defaultPort)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let text = alert?.textFields?.first?.text,
                  let value = UInt16(text) else {
                HostPopup.toast("端口号无效")
                return
            }
            self.settings.port = value
            if self.service.isRunning {
                do { try self.service.restart(withPort: self.settings.port) }
                catch { HostPopup.toast("切换端口失败：\(error.localizedDescription)") }
            }
            self.table.reloadData()
        })
        present(alert, animated: true)
    }

    private func copyText(_ text: String, label: String) {
        UIPasteboard.general.string = text
        HostPopup.toast("已复制\(label)")
    }

    private func confirmRotateToken() {
        let alert = UIAlertController(title: "重新生成令牌？",
                                      message: "旧令牌会立即失效，已经保存旧令牌的网页需要重新填写。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重新生成", style: .destructive) { [weak self] _ in
            self?.service.rotateToken()
            self?.table.reloadData()
            HostPopup.toast("令牌已更新")
        })
        present(alert, animated: true)
    }

    // MARK: - 二维码

    private func qrImage(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

extension WebAccessViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .server: return 4      // 开关 / 端口 / 地址 / 二维码
        case .token:  return 3      // 令牌 / 复制 / 重新生成
        case .guide:  return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .server: return "本地服务"
        case .token:  return "访问令牌"
        case .guide:  return "使用说明"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section)! == .guide else { return nil }
        return "服务只在 App 运行期间监听；Web 控制台与小程序的所有调用都会经过能力网关，安全模式开启时敏感能力仍需在 App 内放行。"
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if Section(rawValue: indexPath.section)! == .server, indexPath.row == 3 {
            return running ? 190 : UITableView.automaticDimension
        }
        if Section(rawValue: indexPath.section)! == .guide {
            return UITableView.automaticDimension
        }
        return 44
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "cell")
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = nil
        cell.imageView?.image = nil

        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .server:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "开启 Web 访问"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = running
                sw.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw

            case 1:
                cell.textLabel?.text = "监听端口"
                cell.detailTextLabel?.text = String(settings.port)
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator

            case 2:
                cell.textLabel?.text = "访问地址"
                if running {
                    cell.detailTextLabel?.text = service.baseURL ?? "未获取到局域网 IP"
                } else {
                    cell.detailTextLabel?.text = "未开启"
                }
                cell.detailTextLabel?.textColor = running ? .secondaryLabel : .tertiaryLabel
                cell.detailTextLabel?.adjustsFontSizeToFitWidth = true
                cell.detailTextLabel?.minimumScaleFactor = 0.7

            default:
                cell.textLabel?.text = nil
                cell.selectionStyle = .none
                let container = UIView()
                if running, let base = service.baseURL, let url = service.accessURL,
                   let qr = qrImage(for: url) {
                    let iv = UIImageView(image: qr)
                    iv.contentMode = .scaleAspectFit
                    iv.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(iv)
                    NSLayoutConstraint.activate([
                        iv.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                        iv.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
                        iv.widthAnchor.constraint(equalToConstant: 150),
                        iv.heightAnchor.constraint(equalToConstant: 150)
                    ])
                    cell.detailTextLabel?.text = base
                } else {
                    let label = UILabel()
                    label.translatesAutoresizingMaskIntoConstraints = false
                    label.font = .systemFont(ofSize: 13)
                    label.textColor = .secondaryLabel
                    label.text = "开启后可扫码在电脑浏览器里打开控制台"
                    label.textAlignment = .center
                    container.addSubview(label)
                    NSLayoutConstraint.activate([
                        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                        label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                        label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
                    ])
                }
                cell.contentView.addSubview(container)
                container.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    container.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    container.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    container.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
                ])
            }

        case .token:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "当前令牌"
                cell.detailTextLabel?.text = masked(settings.token)
                cell.detailTextLabel?.textColor = .secondaryLabel
                cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                cell.selectionStyle = .none

            case 1:
                cell.textLabel?.text = "复制令牌"
                cell.textLabel?.textColor = .label
                cell.accessoryType = .disclosureIndicator

            default:
                cell.textLabel?.text = "重新生成令牌"
                cell.textLabel?.textColor = .systemRed
                cell.accessoryType = .disclosureIndicator
            }

        case .guide:
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.font = .systemFont(ofSize: 13)
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.text = """
            1. 开启服务后，用同一 Wi-Fi 下的浏览器打开访问地址（或扫描上面的二维码）；
            2. Web 控制台复刻了 App 的四个页面：导入应用、应用库、商店、设置；
            3. 在控制台里可直接导入 ZIP、运行小程序、查看设备信息、修改偏好设置；
            4. 小程序页面与 wx.* 能力都通过设备上的能力网关执行，安全模式照常生效；
            5. 服务只在 App 运行期间监听，令牌可随时重新生成。
            """
            cell.selectionStyle = .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .server:
            if indexPath.row == 1 { promptPort() }
            if indexPath.row == 2, let base = service.baseURL { copyText(base, label: "访问地址") }
        case .token:
            if indexPath.row == 1 { copyText(settings.token, label: "令牌") }
            if indexPath.row == 2 { confirmRotateToken() }
        case .guide:
            break
        }
    }

    @objc private func switchChanged(_ sw: UISwitch) {
        toggleServer(sw.isOn)
    }

    private func masked(_ token: String) -> String {
        guard token.count > 10 else { return token }
        let head = token.prefix(6)
        let tail = token.suffix(4)
        return "\(head)••••••\(tail)"
    }
}
