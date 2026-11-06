import UIKit

/// 安全模式横幅：敏感能力被拦截时，从顶部滑入，2.5 秒后自动收起。
/// 挂在 keyWindow 上，不依赖任何特定 VC 的层级。
final class SecurityBanner {
    static let shared = SecurityBanner()
    private var current: UIView?
    private var hideWorkItem: DispatchWorkItem?
    private init() {}

    func show(module: String, appName: String?, onAllowOnce: (() -> Void)? = nil, onTrust: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let window = Self.keyWindow() else { return }

            self.current?.removeFromSuperview()
            self.hideWorkItem?.cancel()

            let name = SecurityMode.displayName(for: module)
            let app = appName.map { "「\($0)」" } ?? "小程序"

            let container = UIView()
            container.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.96)
            container.layer.cornerRadius = 14
            container.layer.cornerCurve = .continuous
            container.translatesAutoresizingMaskIntoConstraints = false

            let icon = UIImageView(image: UIImage(systemName: "hand.raised.fill"))
            icon.tintColor = .white
            icon.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.text = "已拦截：\(app) 使用\(name)"
            label.textColor = .white
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.numberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(icon)
            container.addSubview(label)
            window.addSubview(container)

            var constraints: [NSLayoutConstraint] = [
                container.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 12),
                container.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -12),
                container.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),

                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20),

                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
            ]

            let buttons = UIStackView()
            buttons.axis = .vertical
            buttons.spacing = 4
            buttons.translatesAutoresizingMaskIntoConstraints = false

            if let onAllowOnce = onAllowOnce {
                let btn = makeActionButton("允许本次", filled: false) { [weak self] in
                    onAllowOnce()
                    self?.hide()
                }
                buttons.addArrangedSubview(btn)
            }
            if let onTrust = onTrust {
                let btn = makeActionButton("以后都允许", filled: true) { [weak self] in
                    onTrust()
                    self?.hide()
                }
                buttons.addArrangedSubview(btn)
            }

            if !buttons.arrangedSubviews.isEmpty {
                container.addSubview(buttons)
                constraints += [
                    buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                    buttons.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    label.trailingAnchor.constraint(equalTo: buttons.leadingAnchor, constant: -10)
                ]
            }

            NSLayoutConstraint.activate(constraints)

            container.alpha = 0
            container.transform = CGAffineTransform(translationX: 0, y: -20)
            UIView.animate(withDuration: 0.25) {
                container.alpha = 1
                container.transform = .identity
            }

            self.current = container

            let work = DispatchWorkItem { [weak self] in self?.hide() }
            self.hideWorkItem = work
            // 8 秒：2.5 秒内既要看清文字又要点中按钮，实际做不到，等于把授权入口做成了装饰
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        }
    }

    private func makeActionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(filled ? UIColor.systemOrange : .white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        btn.backgroundColor = filled ? .white : .clear
        btn.layer.borderColor = UIColor.white.cgColor
        btn.layer.borderWidth = filled ? 0 : 1
        btn.layer.cornerRadius = 10
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    private func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let v = self.current else { return }
            UIView.animate(withDuration: 0.2, animations: {
                v.alpha = 0
                v.transform = CGAffineTransform(translationX: 0, y: -20)
            }, completion: { _ in
                v.removeFromSuperview()
                if self.current === v { self.current = nil }
            })
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
