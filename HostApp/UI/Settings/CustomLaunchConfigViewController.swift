import UIKit

/// 定制启动配置页：选应用 + 填参数。
final class CustomLaunchConfigViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var paramsTextView = UITextView()
    private var selectedAppId: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "定制启动"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "保存", style: .done, target: self, action: #selector(save))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "取消", style: .plain, target: self, action: #selector(cancel))

        selectedAppId = AppSettings.shared.customAppId

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

    @objc private func save() {
        guard let id = selectedAppId else {
            HostPopup.toast("请选择一个应用")
            return
        }
        guard AppLibrary.shared.app(id: id) != nil else {
            HostPopup.toast("应用未安装")
            return
        }

        // 校验 JSON
        let text = paramsTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            guard let data = text.data(using: .utf8),
                  let _ = try? JSONSerialization.jsonObject(with: data) else {
                HostPopup.toast("参数不是合法 JSON")
                return
            }
        }

        AppSettings.shared.customAppId = id
        AppSettings.shared.customParams = text.isEmpty ? nil : text
        AppSettings.shared.launchMode = .custom
        dismiss(animated: true)
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }
}

extension CustomLaunchConfigViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? max(AppLibrary.shared.apps.count, 1) : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "选择应用" : "启动参数（JSON，可选）"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 {
            return "启动时应用可通过 wx.getLaunchParams() 读到这里的参数。例：{\"page\": \"detail\", \"id\": 1}"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none

        if indexPath.section == 0 {
            let apps = AppLibrary.shared.apps
            if apps.isEmpty {
                cell.textLabel?.text = "还没有安装任何应用"
                cell.textLabel?.textColor = .secondaryLabel
                return cell
            }
            let app = apps[indexPath.row]
            cell.textLabel?.text = app.name
            cell.textLabel?.textColor = .label
            if app.appId == selectedAppId {
                cell.accessoryType = .checkmark
            }
            return cell
        }

        // 参数输入框（每次重建，避免 cell 复用叠加）
        cell.contentView.subviews.forEach {
            if $0 is UITextView { $0.removeFromSuperview() }
        }
        let tv = UITextView()
        tv.text = AppSettings.shared.customParams ?? ""
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(tv)
        self.paramsTextView = tv
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 4),
            tv.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -4),
            tv.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
            tv.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4)
        ])
        cell.selectionStyle = .none
        return cell

    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == 1 ? 110 : 44
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        let apps = AppLibrary.shared.apps
        guard !apps.isEmpty else { return }
        selectedAppId = apps[indexPath.row].appId
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }
}
