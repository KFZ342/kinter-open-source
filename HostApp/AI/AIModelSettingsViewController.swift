import UIKit

/// AI 模型配置页。
final class AIModelSettingsViewController: UIViewController {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let fields: [(key: String, placeholder: String, isSecure: Bool)] = [
        ("endpoint", "接口地址，如 https://api.openai.com/v1", false),
        ("apiKey", "API Key", true),
        ("model", "模型名，如 gpt-4o-mini", false)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AI 模型"
        view.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        table.register(TextFieldCell.self, forCellReuseIdentifier: "tf")
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

extension AIModelSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return fields.count
        case 1: return 1  // temperature
        case 2: return 1  // 测试连接
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "接口配置"
        case 1: return "生成参数"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "支持任何 OpenAI 兼容接口。地址填到 /v1 即可，会自动补全 /chat/completions。"
        case 1:
            return "temperature 越低越稳定，越高越有创意。"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "tf", for: indexPath) as! TextFieldCell
            let f = fields[indexPath.row]
            let current: String
            switch f.key {
            case "endpoint": current = AISettings.shared.endpoint
            case "apiKey":   current = AISettings.shared.apiKey
            case "model":    current = AISettings.shared.model
            default:         current = ""
            }
            cell.configure(placeholder: f.placeholder, value: current, secure: f.isSecure) { [weak self] newValue in
                self?.save(key: f.key, value: newValue)
            }
            return cell
        }

        if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.text = "Temperature"
            cell.detailTextLabel?.text = String(format: "%.2f", AISettings.shared.temperature)
            let slider = UISlider()
            slider.minimumValue = 0
            slider.maximumValue = 1.5
            slider.value = Float(AISettings.shared.temperature)
            slider.addTarget(self, action: #selector(tempChanged(_:)), for: .valueChanged)
            cell.accessoryView = slider
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = "测试连接"
        cell.textLabel?.textColor = .systemBlue
        cell.accessoryView = nil
        cell.accessoryType = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2 {
            testConnection()
        }
    }

    private func save(key: String, value: String) {
        switch key {
        case "endpoint": AISettings.shared.endpoint = value
        case "apiKey":   AISettings.shared.apiKey = value
        case "model":    AISettings.shared.model = value
        default: break
        }
    }

    @objc private func tempChanged(_ s: UISlider) {
        AISettings.shared.temperature = Double(s.value)
        table.reloadSections(IndexSet(integer: 1), with: .none)
    }

    private func testConnection() {
        guard AISettings.shared.isConfigured else {
            HostPopup.toast("请先填写完整配置")
            return
        }
        HostPopup.toast("正在测试…")
        let client = AIClient()
        client.chat(messages: [
            .init(role: "user", content: "回复两个字：正常")
        ]) { result in
            switch result {
            case .success(let text):
                HostPopup.toast("连接成功：\(String(text.prefix(20)))")
            case .failure(let err):
                HostPopup.modal(title: "连接失败", content: err.localizedDescription,
                                confirmText: "知道了", cancelText: nil) { _ in }
            }
        }
    }
}

/// 带输入框的单元格。
final class TextFieldCell: UITableViewCell, UITextFieldDelegate {
    private let field = UITextField()
    private var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 15)
        field.delegate = self
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(placeholder: String, value: String, secure: Bool, onChange: @escaping (String) -> Void) {
        field.placeholder = placeholder
        field.text = value
        field.isSecureTextEntry = secure
        field.keyboardType = placeholder.contains("https") ? .URL : .default
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        self.onChange = onChange
    }

    @objc private func editingChanged() {
        onChange?(field.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
