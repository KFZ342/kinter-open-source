import UIKit
import UniformTypeIdentifiers

/// 导入界面：选择 ZIP → 校验 → 安装。
final class ImportViewController: UIViewController,
                                   UIDocumentPickerDelegate {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let pickButton = UIButton(type: .system)
    private let statusCard = UIView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "导入应用"
        view.backgroundColor = .systemGroupedBackground
        setupUI()
    }

    private func setupUI() {
        iconView.image = UIImage(systemName: "shippingbox.fill")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "安装小程序"
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "选择一个 .zip 安装包，系统会检查完整性后导入应用库。"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        pickButton.setTitle("选择 ZIP 安装包", for: .normal)
        pickButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        pickButton.backgroundColor = .systemBlue
        pickButton.setTitleColor(.white, for: .normal)
        pickButton.layer.cornerRadius = 12
        pickButton.addTarget(self, action: #selector(openPicker), for: .touchUpInside)
        pickButton.translatesAutoresizingMaskIntoConstraints = false

        statusCard.backgroundColor = .secondarySystemGroupedBackground
        statusCard.layer.cornerRadius = 12
        statusCard.isHidden = true
        statusCard.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .label
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusLabel)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(spinner)

        // AI 入口
        let aiStack = UIStackView()
        aiStack.axis = .horizontal
        aiStack.spacing = 12
        aiStack.distribution = .fillEqually
        aiStack.translatesAutoresizingMaskIntoConstraints = false

        let aiGenBtn = UIButton(type: .system)
        aiGenBtn.setTitle("AI 生成", for: .normal)
        aiGenBtn.setImage(UIImage(systemName: "sparkles"), for: .normal)
        aiGenBtn.tintColor = .white
        aiGenBtn.setTitleColor(.white, for: .normal)
        aiGenBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        aiGenBtn.backgroundColor = .systemPurple
        aiGenBtn.layer.cornerRadius = 12
        aiGenBtn.heightAnchor.constraint(equalToConstant: 46).isActive = true
        aiGenBtn.addTarget(self, action: #selector(openAIGenerate), for: .touchUpInside)
        aiStack.addArrangedSubview(aiGenBtn)

        let aiModelBtn = UIButton(type: .system)
        aiModelBtn.setTitle("模型设置", for: .normal)
        aiModelBtn.setImage(UIImage(systemName: "cpu"), for: .normal)
        aiModelBtn.tintColor = .white
        aiModelBtn.setTitleColor(.white, for: .normal)
        aiModelBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        aiModelBtn.backgroundColor = .systemGray
        aiModelBtn.layer.cornerRadius = 12
        aiModelBtn.addTarget(self, action: #selector(openAIModel), for: .touchUpInside)
        aiStack.addArrangedSubview(aiModelBtn)

        view.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(pickButton)
        view.addSubview(aiStack)
        view.addSubview(statusCard)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -180),
            iconView.widthAnchor.constraint(equalToConstant: 90),
            iconView.heightAnchor.constraint(equalToConstant: 90),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),

            pickButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            pickButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pickButton.widthAnchor.constraint(equalToConstant: 260),
            pickButton.heightAnchor.constraint(equalToConstant: 52),

            aiStack.topAnchor.constraint(equalTo: pickButton.bottomAnchor, constant: 12),
            aiStack.leadingAnchor.constraint(equalTo: pickButton.leadingAnchor),
            aiStack.trailingAnchor.constraint(equalTo: pickButton.trailingAnchor),

            statusCard.topAnchor.constraint(equalTo: aiStack.bottomAnchor, constant: 24),
            statusCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            statusCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
            statusCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

            statusLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -14),

            spinner.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -20)
        ])
    }

    @objc private func openAIGenerate() {
        navigationController?.pushViewController(AgentChatViewController(), animated: true)
    }

    @objc private func openAIModel() {
        navigationController?.pushViewController(AIModelSettingsViewController(), animated: true)
    }

    @objc private func openPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    // MARK: - 选择器回调

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        install(url: url)
    }

    private func install(url: URL) {
        showStatus("正在校验安装包…", loading: true)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try PackageInstaller.shared.install(zipURL: url)
                DispatchQueue.main.async {
                    var msg = "✓ 安装成功：\(result.app.name) v\(result.app.version)"
                    if !result.warnings.isEmpty, AppSettings.shared.showWarnings {
                        msg += "\n\n注意：\n" + result.warnings.joined(separator: "\n")
                    }
                    self.showStatus(msg, loading: false)
                    self.notifyLibraryChanged()
                    if let nav = self.tabBarController?.viewControllers?[1] as? UINavigationController {
                        self.tabBarController?.selectedIndex = 1
                        _ = nav
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showStatus("✗ " + (error.localizedDescription), loading: false)
                }
            }
        }
    }

    private func notifyLibraryChanged() {
        NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
    }

    private func showStatus(_ text: String, loading: Bool) {
        statusCard.isHidden = false
        statusLabel.text = text
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

extension Notification.Name {
    static let appLibraryDidChange = Notification.Name("AppLibraryDidChange")
}
