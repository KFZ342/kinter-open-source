import UIKit

/// 应用库：收藏区 + 分类分组的应用列表 + 搜索 + 长按管理。
final class LibraryViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var groups: [(category: String, apps: [InstalledApp])] = []
    private let emptyLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)
    private var keyword: String = ""

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

        // 搜索栏：按应用名 / appId / 分类实时过滤
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索应用名或 appId"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

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
        var apps = AppLibrary.shared.apps
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty {
            apps = apps.filter {
                $0.name.localizedCaseInsensitiveContains(kw)
                || $0.appId.localizedCaseInsensitiveContains(kw)
                || $0.category.localizedCaseInsensitiveContains(kw)
            }
        }

        var out: [(category: String, apps: [InstalledApp])] = []
        // 收藏单独成组，固定在最前
        let favorites = apps.filter { $0.isFavorite }.sorted { $0.name < $1.name }
        if !favorites.isEmpty { out.append((category: "收藏", apps: favorites)) }

        let byCat = Dictionary(grouping: apps, by: { $0.category })
        out += byCat.keys.sorted().map { cat in
            (category: cat, apps: byCat[cat]!.sorted { $0.name < $1.name })
        }
        groups = out

        table.reloadData()
        emptyLabel.isHidden = !apps.isEmpty
        table.isHidden = apps.isEmpty
    }

    private func launch(_ app: InstalledApp) {
        AppSettings.shared.lastOpenedAppId = app.appId
        AppLibrary.shared.recordLaunch(appId: app.appId)
        MiniAppLauncher.open(app: app, from: self)
    }

    private func showMultiTaskMenu(_ app: InstalledApp) {
        AppSettings.shared.lastOpenedAppId = app.appId
        AppLibrary.shared.recordLaunch(appId: app.appId)
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

extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        keyword = searchController.searchBar.text ?? ""
        reload()
    }
}

extension LibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { groups.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups[section].apps.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let g = groups[section]
        return "\(g.category)（\(g.apps.count)）"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AppCell.reuseID, for: indexPath) as! AppCell
        let app = groups[indexPath.section].apps[indexPath.row]
        cell.configure(app: app)
        cell.onLaunch = { [weak self] in self?.launch(app) }
        cell.onManage = { [weak self] in self?.manage(app) }
        cell.onMultiTask = { [weak self] in self?.showMultiTaskMenu(app) }
        cell.onFavorite = { [weak self, weak cell] in
            guard let self = self, let cell = cell else { return }
            let now = AppLibrary.shared.toggleFavorite(appId: app.appId)
            cell.setFavorite(now)
            self.reload()
        }
        return cell
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let app = groups[indexPath.section].apps[indexPath.row]
        let fav = UIContextualAction(style: .normal, title: app.isFavorite ? "取消收藏" : "收藏") { _, _, done in
            AppLibrary.shared.toggleFavorite(appId: app.appId)
            self.reload()
            done(true)
        }
        fav.backgroundColor = .systemYellow
        let del = UIContextualAction(style: .destructive, title: "卸载") { _, _, done in
            AppLibrary.shared.remove(appId: app.appId)
            self.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [fav, del])
    }
}

// MARK: - 应用单元格

final class AppCell: UITableViewCell {
    static let reuseID = "AppCell"

    var onLaunch: (() -> Void)?
    var onManage: (() -> Void)?
    var onMultiTask: (() -> Void)?
    var onFavorite: (() -> Void)?

    private let nameLabel = UILabel()
    private let aiBadge = UILabel()
    private let metaLabel = UILabel()
    private let launchBtn = UIButton(type: .system)
    private let manageBtn = UIButton(type: .system)
    private let favBtn = UIButton(type: .system)
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

        favBtn.tintColor = .systemYellow
        favBtn.addTarget(self, action: #selector(tapFavorite), for: .touchUpInside)

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
        favBtn.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconView)
        contentView.addSubview(textStack)
        contentView.addSubview(favBtn)
        contentView.addSubview(manageBtn)
        contentView.addSubview(launchBtn)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: favBtn.leadingAnchor, constant: -8),

            launchBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            launchBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            launchBtn.widthAnchor.constraint(equalToConstant: 44),
            launchBtn.heightAnchor.constraint(equalToConstant: 44),

            manageBtn.trailingAnchor.constraint(equalTo: launchBtn.leadingAnchor, constant: -4),
            manageBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            manageBtn.widthAnchor.constraint(equalToConstant: 32),
            manageBtn.heightAnchor.constraint(equalToConstant: 44),

            favBtn.trailingAnchor.constraint(equalTo: manageBtn.leadingAnchor, constant: -2),
            favBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            favBtn.widthAnchor.constraint(equalToConstant: 32),
            favBtn.heightAnchor.constraint(equalToConstant: 44),

            aiBadge.widthAnchor.constraint(equalToConstant: 24),
            aiBadge.heightAnchor.constraint(equalToConstant: 16),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(app: InstalledApp) {
        nameLabel.text = app.name
        aiBadge.isHidden = !app.isAIGenerated

        var parts: [String] = ["v\(app.version)"]
        if let stars = app.ratingStars { parts.append(stars) }
        if app.launchCount > 0 { parts.append("打开 \(app.launchCount) 次") }
        if app.disabledCapabilities.count > 0 { parts.append("已禁用 \(app.disabledCapabilities.count) 项权限") }
        metaLabel.text = parts.joined(separator: " · ")

        setFavorite(app.isFavorite)
        applyIcon(app: app)
    }

    func setFavorite(_ favorite: Bool) {
        let name = favorite ? "star.fill" : "star"
        favBtn.setImage(UIImage(systemName: name), for: .normal)
        favBtn.tintColor = favorite ? .systemYellow : .systemGray4
    }

    /// 图标优先级：图标文件 > manifest.iconSymbol + iconColor > 默认占位
    private func applyIcon(app: InstalledApp) {
        iconView.contentMode = .scaleAspectFill
        iconView.backgroundColor = .tertiarySystemFill

        if let url = app.iconURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            iconView.image = image
            return
        }
        if let symbol = app.iconSymbol,
           let image = UIImage(systemName: symbol) {
            let color = app.iconColor.flatMap { UIColor(hex: $0) } ?? .systemBlue
            iconView.backgroundColor = color.withAlphaComponent(0.16)
            iconView.image = image
            iconView.tintColor = color
            iconView.contentMode = .center
            return
        }
        iconView.image = UIImage(systemName: "app.dashed")
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .center
    }

    @objc private func tapLaunch() { onLaunch?() }
    @objc private func tapFavorite() { onFavorite?() }

    @objc private func longPressLaunch(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onMultiTask?()
    }
    @objc private func tapManage() { onManage?() }
}
