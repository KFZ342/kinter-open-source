import UIKit

/// 应用库：分类分组的应用列表 + 启动按钮 + 长按管理。
final class LibraryViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var groups: [(category: String, apps: [InstalledApp])] = []
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "应用库"
        view.backgroundColor = .systemGroupedBackground

        table.dataSource = self
        table.delegate = self
        table.register(AppCell.self, forCellReuseIdentifier: AppCell.reuseID)
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        emptyLabel.text = "还没有安装任何应用\n去「导入」页添加 ZIP 安装包"
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

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reload),
                                               name: .appLibraryDidChange,
                                               object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func reload() {
        let apps = AppLibrary.shared.apps
        let byCat = Dictionary(grouping: apps, by: { $0.category })
        groups = byCat.keys.sorted().map { cat in
            (category: cat, apps: byCat[cat]!.sorted { $0.name < $1.name })
        }
        table.reloadData()
        emptyLabel.isHidden = !apps.isEmpty
        table.isHidden = apps.isEmpty
    }
}

extension LibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { groups.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups[section].apps.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups[section].category
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AppCell.reuseID, for: indexPath) as! AppCell
        let app = groups[indexPath.section].apps[indexPath.row]
        cell.configure(app: app)
        cell.onLaunch = { [weak self] in self?.launch(app) }
        cell.onManage = { [weak self] in self?.manage(app) }
        cell.onMultiTask = { [weak self] in self?.showMultiTaskMenu(app) }
        return cell
    }

    private func launch(_ app: InstalledApp) {
        AppSettings.shared.lastOpenedAppId = app.appId
        MiniAppLauncher.open(app: app, from: self)
    }

    private func showMultiTaskMenu(_ app: InstalledApp) {
        AppSettings.shared.lastOpenedAppId = app.appId
        let vc = WindowManagerViewController()
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true) {
            vc.addApp(app)
        }
    }

    private func manage(_ app: InstalledApp) {
        let vc = AppManageViewController(app: app)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - 应用单元格

final class AppCell: UITableViewCell {
    static let reuseID = "AppCell"

    var onLaunch: (() -> Void)?
    var onManage: (() -> Void)?
    var onMultiTask: (() -> Void)?

    private let nameLabel = UILabel()
    private let aiBadge = UILabel()
    private let metaLabel = UILabel()
    private let launchBtn = UIButton(type: .system)
    private let manageBtn = UIButton(type: .system)
    private let iconView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 10
        iconView.layer.cornerCurve = .continuous
        iconView.backgroundColor = .tertiarySystemFill
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        aiBadge.text = "AI"
        aiBadge.font = .systemFont(ofSize: 10, weight: .bold)
        aiBadge.textColor = .white
        aiBadge.backgroundColor = .systemPurple
        aiBadge.textAlignment = .center
        aiBadge.layer.cornerRadius = 4
        aiBadge.layer.cornerCurve = .continuous
        aiBadge.clipsToBounds = true
        aiBadge.translatesAutoresizingMaskIntoConstraints = false
        aiBadge.isHidden = true
        metaLabel.font = .systemFont(ofSize: 13)
        metaLabel.textColor = .secondaryLabel

        launchBtn.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        launchBtn.tintColor = .systemGreen
        launchBtn.addTarget(self, action: #selector(tapLaunch), for: .touchUpInside)

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressLaunch(_:)))
        lp.minimumPressDuration = 0.5
        launchBtn.addGestureRecognizer(lp)

        manageBtn.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        manageBtn.tintColor = .systemGray
        manageBtn.addTarget(self, action: #selector(tapManage), for: .touchUpInside)

        // 名称行：nameLabel + aiBadge
        let nameRow = UIStackView(arrangedSubviews: [nameLabel, aiBadge])
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [nameRow, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        launchBtn.translatesAutoresizingMaskIntoConstraints = false
        manageBtn.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconView)
        contentView.addSubview(textStack)
        contentView.addSubview(manageBtn)
        contentView.addSubview(launchBtn)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: manageBtn.leadingAnchor, constant: -8),

            launchBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            launchBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            launchBtn.widthAnchor.constraint(equalToConstant: 44),
            launchBtn.heightAnchor.constraint(equalToConstant: 44),

            manageBtn.trailingAnchor.constraint(equalTo: launchBtn.leadingAnchor, constant: -4),
            manageBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            manageBtn.widthAnchor.constraint(equalToConstant: 36),
            manageBtn.heightAnchor.constraint(equalToConstant: 44),

            aiBadge.widthAnchor.constraint(equalToConstant: 24),
            aiBadge.heightAnchor.constraint(equalToConstant: 16),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(app: InstalledApp) {
        nameLabel.text = app.name
        aiBadge.isHidden = !app.isAIGenerated
        let disabled = app.disabledCapabilities.count
        var meta = "v\(app.version) · \(app.appId)"
        if disabled > 0 { meta += " · 已禁用 \(disabled) 项权限" }
        metaLabel.text = meta

        // 图标：有则加载，无则用占位符
        if let url = app.iconURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            iconView.image = image
        } else {
            iconView.image = UIImage(systemName: "app.dashed")
            iconView.tintColor = .tertiaryLabel
            iconView.contentMode = .center
        }
    }

    @objc private func tapLaunch() { onLaunch?() }

    @objc private func longPressLaunch(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onMultiTask?()
    }
    @objc private func tapManage() { onManage?() }
}
