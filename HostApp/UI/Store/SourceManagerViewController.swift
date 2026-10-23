import UIKit

/// 源管理：添加/删除商店源。
final class SourceManagerViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var sources: [StoreSource] = []
    private var loading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "源管理"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addSource))

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

        reload()
    }

    private func reload() {
        sources = StoreManager.shared.sources
        table.reloadData()
    }

    @objc private func addSource() {
        let alert = UIAlertController(title: "添加源",
                                      message: "填入 index.json 的完整 URL",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https://cdn.jsdelivr.net/gh/user/repo@main/index.json"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "添加", style: .default) { [weak self] _ in
            guard let url = alert.textFields?.first?.text, !url.isEmpty else { return }
            self?.performAdd(url: url)
        })
        present(alert, animated: true)
    }

    private func performAdd(url: String) {
        do {
            try StoreManager.shared.addSource(url: url)
            reload()
            // 拉取一次
            refresh()
        } catch {
            HostPopup.toast(error.localizedDescription)
        }
    }

    private func refresh() {
        guard !loading else { return }
        loading = true
        table.refreshControl?.beginRefreshing()
        StoreManager.shared.refreshAll { [weak self] in
            guard let self = self else { return }
            self.loading = false
            self.table.refreshControl?.endRefreshing()
            self.reload()
        }
    }
}

extension SourceManagerViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(sources.count, 1)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "已添加的源"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "只添加你信任的源。应用会从源下载 ZIP 并校验 SHA256。建议使用 jsDelivr CDN 地址（cdn.jsdelivr.net）以获得更稳定的访问。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none

        guard !sources.isEmpty else {
            cell.textLabel?.text = "还没有添加任何源"
            cell.textLabel?.textColor = .secondaryLabel
            return cell
        }

        let src = sources[indexPath.row]
        cell.textLabel?.text = src.name
        cell.textLabel?.textColor = .label

        // 右侧状态：成功显示时间，失败显示红色感叹号
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        if let err = src.lastError, !err.isEmpty {
            label.text = "失败"
            label.textColor = .systemRed
        } else if let t = src.lastFetchedAt {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            label.text = fmt.string(from: t)
            label.textColor = .secondaryLabel
        } else {
            label.text = "未拉取"
            label.textColor = .tertiaryLabel
        }
        label.sizeToFit()
        cell.accessoryView = label

        return cell
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, !sources.isEmpty else { return }
        let src = sources[indexPath.row]
        StoreManager.shared.removeSource(url: src.url)
        reload()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !sources.isEmpty else { return }
        let src = sources[indexPath.row]
        let alert = UIAlertController(title: src.name, message: src.url, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "刷新", style: .default) { [weak self] _ in
            self?.refresh()
        })
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            StoreManager.shared.removeSource(url: src.url)
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(alert, animated: true)
    }
}
