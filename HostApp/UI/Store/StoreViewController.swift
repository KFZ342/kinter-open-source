import UIKit

/// 商店主页：展示所有源聚合后的应用列表。
final class StoreViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var groups: [(category: String, apps: [StoreApp])] = []
    private let emptyLabel = UILabel()
    private var loading = false
    /// 上次自动刷新的时间，用于节流
    private var lastAutoRefresh: Date?
    /// 自动刷新进行中标记（与手动刷新的 loading 分开）
    private var isAutoRefreshing = false
    /// 自动刷新最小间隔（秒）
    private let autoRefreshInterval: TimeInterval = 30

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "商店"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain, target: self, action: #selector(openSources))

        table.dataSource = self
        table.delegate = self
        table.register(StoreAppCell.self, forCellReuseIdentifier: StoreAppCell.reuseID)
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(refresh), for: .valueChanged)
        table.refreshControl = rc

        emptyLabel.text = "还没有应用\n点右上角配置源，或下拉刷新"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])

        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        autoRefreshIfNeeded()
    }

    @objc private func openSources() {
        navigationController?.pushViewController(SourceManagerViewController(), animated: true)
    }

    /// 进入页面时自动刷新，带节流，静默执行
    private func autoRefreshIfNeeded() {
        // 没有源就不刷
        guard !StoreManager.shared.sources.isEmpty else { return }
        // 任一刷新进行中就跳过
        guard !loading, !isAutoRefreshing else { return }
        // 节流
        if let last = lastAutoRefresh, Date().timeIntervalSince(last) < autoRefreshInterval {
            return
        }
        lastAutoRefresh = Date()

        // 静默刷新
        isAutoRefreshing = true
        StoreManager.shared.refreshAll { [weak self] in
            guard let self = self else { return }
            self.isAutoRefreshing = false
            self.reload()
        }
    }

    @objc private func refresh() {
        guard !loading, !isAutoRefreshing else {
            table.refreshControl?.endRefreshing()
            return
        }
        loading = true
        lastAutoRefresh = Date()
        StoreManager.shared.refreshAll { [weak self] in
            guard let self = self else { return }
            self.loading = false
            self.table.refreshControl?.endRefreshing()
            self.reload()
        }
    }

    private func reload() {
        groups = StoreManager.shared.appsByCategory
        table.reloadData()
        let empty = groups.isEmpty
        emptyLabel.isHidden = !empty
        table.isHidden = empty
    }
}

extension StoreViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { groups.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups[section].apps.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups[section].category
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: StoreAppCell.reuseID, for: indexPath) as! StoreAppCell
        let app = groups[indexPath.section].apps[indexPath.row]
        cell.configure(app: app)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let app = groups[indexPath.section].apps[indexPath.row]
        presentInstall(for: app)
    }

    private func presentInstall(for app: StoreApp) {
        let installed = AppLibrary.shared.app(id: app.appId)
        let isUpdate = installed != nil
        var msg = app.description ?? ""
        if let size = app.size {
            msg += String(format: "\n\n大小：%.1f KB", Double(size) / 1024)
        }
        msg += "\n版本：\(app.version)"
        if isUpdate {
            msg += "\n已安装：\(installed!.version)"
        }

        let alert = UIAlertController(title: app.name,
                                      message: msg,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: isUpdate ? "更新" : "安装", style: .default) { [weak self] _ in
            self?.doInstall(app)
        })
        present(alert, animated: true)
    }

    private func doInstall(_ app: StoreApp) {
        HostPopup.toast("正在下载…")
        StoreManager.shared.downloadAndInstall(app) { result in
            switch result {
            case .success(let installed):
                HostPopup.toast("已安装：\(installed.name)")
            case .failure(let err):
                HostPopup.modal(title: "安装失败",
                                content: err.localizedDescription,
                                confirmText: "知道了", cancelText: nil) { _ in }
            }
        }
    }
}

/// 商店应用单元格。
final class StoreAppCell: UITableViewCell {
    static let reuseID = "StoreAppCell"

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let versionLabel = UILabel()
    private let descLabel = UILabel()
    private let actionBtn = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default

        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 10
        iconView.layer.cornerCurve = .continuous
        iconView.backgroundColor = .tertiarySystemFill
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabel
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .tertiaryLabel
        descLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [nameLabel, versionLabel, descLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        actionBtn.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
        actionBtn.tintColor = .systemBlue
        actionBtn.translatesAutoresizingMaskIntoConstraints = false
        actionBtn.addTarget(self, action: #selector(noop), for: .touchUpInside)

        contentView.addSubview(iconView)
        contentView.addSubview(textStack)
        contentView.addSubview(actionBtn)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionBtn.leadingAnchor, constant: -8),

            actionBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            actionBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionBtn.widthAnchor.constraint(equalToConstant: 32),
            actionBtn.heightAnchor.constraint(equalToConstant: 32),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func noop() {}

    private var iconTask: URLSessionDataTask?

    func configure(app: StoreApp) {
        nameLabel.text = app.name
        versionLabel.text = "v\(app.version)"
        descLabel.text = app.subtitle ?? app.description ?? ""

        // 已安装状态
        if let installed = AppLibrary.shared.app(id: app.appId) {
            if StoreManager.shared.compareVersion(app.version, installed.version) > 0 {
                actionBtn.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
                actionBtn.tintColor = .systemGreen
            } else {
                actionBtn.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
                actionBtn.tintColor = .systemGray
            }
        } else {
            actionBtn.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            actionBtn.tintColor = .systemBlue
        }

        // 异步加载图标
        iconTask?.cancel()
        iconView.image = UIImage(systemName: "app.dashed")
        iconView.tintColor = .tertiaryLabel
        if let urlStr = app.iconURL, let url = URL(string: urlStr) {
            iconTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.iconView.image = img
                    self?.iconView.tintColor = nil
                }
            }
            iconTask?.resume()
        }
    }
}
