import UIKit

/// 安装前预览页：类 Android 原生安装器的权限确认单。
final class InstallPreviewViewController: UIViewController {

    private let zipURL: URL
    private let preview: PackagePreview
    private let onConfirm: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    /// 合并后的权限列表项
    private var items: [(icon: String, text: String)] = []

    init(zipURL: URL, preview: PackagePreview, onConfirm: (() -> Void)? = nil) {
        self.zipURL = zipURL
        self.preview = preview
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildItems()
        setupUI()
    }

    // MARK: - 构建列表数据

    private func buildItems() {
        // 高危：通讯录、麦克风、剪贴板等
        for cap in preview.sensitiveCapabilities {
            items.append((icon: iconFor(cap), text: textFor(cap)))
        }
        // 中危：相机、相册、定位
        for cap in preview.standardCapabilities {
            items.append((icon: iconFor(cap), text: textFor(cap)))
        }
        // 普通：网络等
        for cap in preview.normalCapabilities {
            // 网络能力太常见，不放进权限列表（显得像吓唬用户），只在后台记录
            if cap == "http" || cap == "upload" || cap == "websocket" { continue }
            items.append((icon: iconFor(cap), text: textFor(cap)))
        }
    }

    private func iconFor(_ cap: String) -> String {
        switch cap {
        case "camera", "photo", "savePhoto", "videoRecord": return "camera.fill"
        case "microphone", "speech": return "mic.fill"
        case "location": return "location.fill"
        case "contacts": return "person.crop.circle.fill"
        case "calendar", "reminder": return "calendar"
        case "health": return "heart.fill"
        case "motion": return "figure.walk"
        case "clipboard", "clipboardImage": return "doc.on.clipboard"
        case "bluetooth", "bluetoothScan": return "wave.3.right"
        case "battery": return "battery.100"
        case "deviceInfo": return "info.circle.fill"
        case "network": return "wifi"
        case "vibrate": return "iphone.radiowaves.left.and.right"
        case "brightness": return "sun.max.fill"
        case "screenAwake": return "display"
        case "share": return "square.and.arrow.up"
        case "openURL": return "link"
        default: return "app.badge.fill"
        }
    }

    private func textFor(_ cap: String) -> String {
        switch cap {
        case "camera": return "使用相机"
        case "photo": return "读取你的照片"
        case "savePhoto": return "保存图片到相册"
        case "videoRecord": return "录制视频"
        case "microphone": return "使用麦克风"
        case "speech": return "语音识别"
        case "location": return "获取你的位置"
        case "contacts": return "读取你的通讯录"
        case "calendar": return "读取你的日历"
        case "reminder": return "读取你的提醒事项"
        case "health": return "读取健康数据"
        case "motion": return "读取运动数据"
        case "clipboard", "clipboardImage": return "读取你的剪贴板"
        case "bluetooth", "bluetoothScan": return "使用蓝牙"
        case "battery": return "读取电池信息"
        case "deviceInfo": return "读取设备信息"
        case "network": return "读取网络状态"
        case "vibrate": return "控制震动"
        case "brightness": return "调整屏幕亮度"
        case "screenAwake": return "保持屏幕常亮"
        case "share": return "调用系统分享"
        case "openURL": return "打开外部链接"
        default: return "使用 \(SecurityPolicy.displayName(for: cap)) 能力"
        }
    }

    // MARK: - 布局

    private func setupUI() {
        // 顶部标题区
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = preview.manifest.name
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let msgLabel = UILabel()
        msgLabel.text = "是否安装此应用？它将获得以下访问权限："
        msgLabel.font = .systemFont(ofSize: 14)
        msgLabel.textColor = .secondaryLabel
        msgLabel.numberOfLines = 0
        msgLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleLabel)
        header.addSubview(msgLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),

            msgLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            msgLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            msgLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            msgLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -16)
        ])

        // 权限列表
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.isScrollEnabled = false // 列表通常不长，如果长可以在外层套 ScrollView
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PermCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        // 底部按钮区（Liquid Glass）
        let footer = UIView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = LiquidGlassButton(title: "取消", style: .secondary)
        cancelBtn.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        let installBtn = LiquidGlassButton(title: "安装", style: .primary)
        installBtn.addTarget(self, action: #selector(didTapInstall), for: .touchUpInside)
        installBtn.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(cancelBtn)
        footer.addSubview(installBtn)
        NSLayoutConstraint.activate([
            cancelBtn.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            cancelBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            cancelBtn.heightAnchor.constraint(equalToConstant: 50),

            installBtn.leadingAnchor.constraint(equalTo: cancelBtn.trailingAnchor, constant: 16),
            installBtn.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24),
            installBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            installBtn.heightAnchor.constraint(equalToConstant: 50),
            
            // 确保两个按钮等宽
            cancelBtn.widthAnchor.constraint(equalTo: installBtn.widthAnchor)
        ])

        view.addSubview(header)
        view.addSubview(tableView)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 90)
        ])
    }

    @objc private func didTapCancel() {
        dismiss(animated: true)
    }

    @objc private func didTapInstall() {
        dismiss(animated: true) { [weak self] in
            self?.onConfirm?()
        }
    }
}

// MARK: - TableView

extension InstallPreviewViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PermCell", for: indexPath)
        let item = items[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = item.text
        config.textProperties.font = .systemFont(ofSize: 15)
        // 使用系统图标，颜色灰色，类似原生设置页
        config.image = UIImage(systemName: item.icon)
        config.imageProperties.tintColor = .secondaryLabel
        config.imageProperties.maximumSize = CGSize(width: 20, height: 20)
        config.imageToTextPadding = 16
        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        return cell
    }
}

// MARK: - Liquid Glass Button

final class LiquidGlassButton: UIControl {
    enum Style {
        case primary   // 主按钮（蓝色玻璃）
        case secondary // 次按钮（透明玻璃）
    }

    private let blurView = UIVisualEffectView(effect: nil)
    private let titleLabel = UILabel()
    private let highlightLayer = CAGradientLayer()
    private let style: Style

    init(title: String, style: Style) {
        self.style = style
        super.init(frame: .zero)

        // 毛玻璃底
        let blurEffect: UIBlurEffect
        if style == .primary {
            blurEffect = UIBlurEffect(style: .systemThinMaterialLight)
            blurView.contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.75)
        } else {
            blurEffect = UIBlurEffect(style: .systemThickMaterial)
            blurView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        }
        blurView.effect = blurEffect
        blurView.isUserInteractionEnabled = false
        blurView.layer.cornerRadius = 16
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        // 边缘高光（模拟玻璃边缘折射）
        layer.borderWidth = 1.0
        layer.borderColor = style == .primary ? UIColor.white.withAlphaComponent(0.4).cgColor : UIColor.white.withAlphaComponent(0.6).cgColor
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        // 文字
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = style == .primary ? .white : .label
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // 按压交互
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            self.alpha = 0.8
        }
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 2.0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = .identity
            self.alpha = 1.0
        }
    }
}

