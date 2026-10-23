import UIKit

/// 应用管理：分类设置 + 权限开关 + 卸载。
final class AppManageViewController: UIViewController {

    private var app: InstalledApp
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var permissionIDs: [String] = []

    init(app: InstalledApp) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
        // 从 manifest 读取声明的能力
        if let data = try? Data(contentsOf: app.manifestURL),
           let manifest = try? ManifestParser.parse(data: data),
           let caps = manifest.capabilities {
            permissionIDs = caps.keys.sorted()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = app.name
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

extension AppManageViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 4 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1                 // 分类
        case 1: return 1                 // 桌面快捷方式
        case 2: return max(permissionIDs.count, 1)
        default: return 1                // 卸载
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "分类"
        case 1: return "桌面"
        case 2: return "权限（\(permissionIDs.count) 项）"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 2 {
            return "关闭某项权限后，应用调用该能力会立即失败。模拟器不支持的能力仍会列出，真机上才生效。"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.textLabel?.textColor = .label

        switch indexPath.section {
        case 0:
            cell.textLabel?.text = app.category
            cell.accessoryType = .disclosureIndicator

        case 1:
            cell.textLabel?.text = "添加到主屏幕"
            cell.textLabel?.textColor = .systemBlue
            cell.accessoryType = .disclosureIndicator

        case 2:
            guard !permissionIDs.isEmpty else {
                cell.textLabel?.text = "未声明任何能力"
                cell.textLabel?.textColor = .secondaryLabel
                return cell
            }
            let cap = permissionIDs[indexPath.row]
            let info = PermissionCatalog.info(cap)
            let enabled = !app.disabledCapabilities.contains(cap)

            var title = info?.displayName ?? cap
            if let sim = info?.simulator, sim != .available {
                title += "（\(sim.displayName)）"
            }
            cell.textLabel?.text = title
            cell.textLabel?.textColor = enabled ? .label : .secondaryLabel

            let sw = UISwitch()
            sw.isOn = enabled
            sw.tag = indexPath.row
            sw.addTarget(self, action: #selector(toggle(_:)), for: .valueChanged)
            cell.accessoryView = sw

        default:
            cell.textLabel?.text = "卸载应用"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            promptCategory()
        } else if indexPath.section == 1 {
            addToHomeScreen()
        } else if indexPath.section == 3 {
            confirmUninstall()
        }
    }

    @objc private func toggle(_ sw: UISwitch) {
        guard sw.tag < permissionIDs.count else { return }
        let cap = permissionIDs[sw.tag]
        AppLibrary.shared.setCapability(cap, enabled: sw.isOn, for: app.appId)
        app = AppLibrary.shared.app(id: app.appId) ?? app
        table.reloadSections(IndexSet(integer: 1), with: .none)
    }

    private func promptCategory() {
        let alert = UIAlertController(title: "设置分类", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = self.app.category
            tf.placeholder = "例如：工具、游戏、工作"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            self.app.category = text.isEmpty ? "未分类" : text
            AppLibrary.shared.update(self.app)
            self.table.reloadSections(IndexSet(integer: 0), with: .automatic)
            NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        })
        present(alert, animated: true)
    }

    /// 生成 Web Clip 描述文件并弹出系统安装面板
    private func addToHomeScreen() {
        do {
            let url = try WebClipGenerator.generate(for: app)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = controller.popoverPresentationController {
                pop.sourceView = view
                pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            present(controller, animated: true)
        } catch {
            HostPopup.modal(title: "无法生成",
                            content: error.localizedDescription,
                            confirmText: "知道了", cancelText: nil) { _ in }
        }
    }

    private func confirmUninstall() {
        let alert = UIAlertController(title: "卸载 \(app.name)",
                                      message: "应用文件与数据将被删除，无法恢复。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "卸载", style: .destructive) { _ in
            AppLibrary.shared.remove(appId: self.app.appId)
            NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}
