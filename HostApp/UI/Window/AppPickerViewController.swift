import UIKit

/// 选择应用加入工作区。
final class AppPickerViewController: UIViewController {

    var onPick: ((InstalledApp) -> Void)?

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var apps: [InstalledApp] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "添加应用"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))

        apps = AppLibrary.shared.apps

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

    @objc private func cancel() {
        dismiss(animated: true)
    }
}

extension AppPickerViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(apps.count, 1)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        apps.isEmpty ? nil : "已安装的小程序"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        guard !apps.isEmpty else {
            cell.textLabel?.text = "还没有安装任何应用"
            cell.textLabel?.textColor = .secondaryLabel
            return cell
        }
        let app = apps[indexPath.row]
        cell.textLabel?.text = app.name
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = app.appId
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !apps.isEmpty else { return }
        let app = apps[indexPath.row]
        dismiss(animated: true) { [weak self] in
            self?.onPick?(app)
        }
    }
}
