import UIKit

/// 安全模式横幅：敏感能力被拦截时从顶部滑入，**停在屏幕上等你决定**。
///
/// 旧版有两个毛病：文字左右各挂了一条 trailing 约束（互相冲突，按钮被挤没），
/// 而且 8 秒自动收起 —— 还没看清就没了，等于没有授权入口。
/// 现在：单列布局、按钮满宽 38pt、只在点按钮或按关闭时收起。
final class SecurityBanner {
    static let shared = SecurityBanner()
    private var current: UIView?

    private init() {}

    func show(module: String,
              appName: String?,
              onAllowOnce: (() -> Void)? = nil,
              onTrust: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let window = Self.presentingWindow() else { return }
            // 兜底：横幅只是提示，渲染失败也不该把宿主带走
            let thrown = ObjCExceptionCatcher.catchException {
                self.render(module: module, appName: appName,
                            onAllowOnce: onAllowOnce, onTrust: onTrust, in: window)
            }
            if let t = thrown {
                NSLog("[SecurityBanner] 横幅未能显示：%@", t)
            }
        }
    }

    private func render(module: String, appName: String?,
                        onAllowOnce: (() -> Void)?, onTrust: (() -> Void)?,
                        in window: UIWindow) {
            self.current?.removeFromSuperview()

            let name = SecurityMode.displayName(for: module)
            let who = appName.map { "「\($0)」" } ?? "某个小程序"

            let card = UIView()
            card.backgroundColor = .systemOrange
            card.layer.cornerRadius = 16
            card.layer.cornerCurve = .continuous
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = 0.18
            card.layer.shadowRadius = 12
            card.layer.shadowOffset = CGSize(width: 0, height: 5)
            card.translatesAutoresizingMaskIntoConstraints = false

            let icon = UIImageView(image: UIImage(systemName: "hand.raised.fill"))
            icon.tintColor = .white
            icon.contentMode = .scaleAspectFit
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.setContentHuggingPriority(.required, for: .horizontal)

            let title = UILabel()
            title.text = "\(who)想使用\(name)"
            title.textColor = .white
            title.font = .systemFont(ofSize: 15, weight: .semibold)
            title.numberOfLines = 0

            let hint = UILabel()
            hint.text = onAllowOnce == nil
                ? "安全模式已拦截，这类能力不放行"
                : "放行后请回小程序里再操作一次"
            hint.textColor = UIColor.white.withAlphaComponent(0.92)
            hint.font = .systemFont(ofSize: 12)
            hint.numberOfLines = 0

            let texts = UIStackView(arrangedSubviews: [title, hint])
            texts.axis = .vertical
            texts.spacing = 3

            let header = UIStackView(arrangedSubviews: [icon, texts])
            header.axis = .horizontal
            header.spacing = 10
            header.alignment = .top

            let close = UIButton(type: .system)
            close.setImage(UIImage(systemName: "xmark"), for: .normal)
            close.tintColor = UIColor.white.withAlphaComponent(0.85)
            close.translatesAutoresizingMaskIntoConstraints = false
            close.widthAnchor.constraint(equalToConstant: 30).isActive = true
            close.heightAnchor.constraint(equalToConstant: 30).isActive = true
            close.addAction(UIAction { [weak self] _ in self?.hide() }, for: .touchUpInside)

            let topRow = UIStackView(arrangedSubviews: [header, close])
            topRow.axis = .horizontal
            topRow.alignment = .top
            topRow.spacing = 8

            let buttons = UIStackView()
            buttons.axis = .horizontal
            buttons.spacing = 8
            buttons.distribution = .fillEqually
            buttons.translatesAutoresizingMaskIntoConstraints = false
            buttons.heightAnchor.constraint(equalToConstant: 38).isActive = true

            if let onAllowOnce = onAllowOnce {
                buttons.addArrangedSubview(makeButton("允许本次", filled: true) { [weak self] in
                    onAllowOnce()
                    self?.hide()
                })
            }
            if let onTrust = onTrust {
                buttons.addArrangedSubview(makeButton("以后都允许", filled: false) { [weak self] in
                    onTrust()
                    self?.hide()
                })
            }
            buttons.isHidden = buttons.arrangedSubviews.isEmpty

            let stack = UIStackView(arrangedSubviews: [topRow, buttons])
            stack.axis = .vertical
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(stack)

            var constraints: [NSLayoutConstraint] = [
                stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
                stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 22),
                card.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
                card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                card.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
            ]
            // iPad 上别拉成一整条；iPhone 上左右各留 12
            let edge = card.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 12)
            let edge2 = card.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -12)
            let wide = card.widthAnchor.constraint(equalTo: window.widthAnchor, constant: -24)
            wide.priority = UILayoutPriority(750)
            constraints += [edge, edge2, wide]
            // 先入窗口再激活：card 与 window 没有共同祖先时激活跨视图约束会抛 NSException
            window.addSubview(card)
            self.current = card
            NSLayoutConstraint.activate(constraints)

            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: -24)
            UIView.animate(withDuration: 0.28, delay: 0,
                           usingSpringWithDamping: 0.86, initialSpringVelocity: 0.3,
                           options: [.curveEaseOut], animations: {
                card.alpha = 1
                card.transform = .identity
            }, completion: nil)
        }
    }

    private func makeButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.layer.cornerRadius = 10
        btn.layer.cornerCurve = .continuous
        if filled {
            btn.backgroundColor = .white
            btn.setTitleColor(.systemOrange, for: .normal)
        } else {
            btn.backgroundColor = UIColor.white.withAlphaComponent(0.16)
            btn.setTitleColor(.white, for: .normal)
            btn.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
            btn.layer.borderWidth = 1
        }
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    private func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let v = self.current else { return }
            UIView.animate(withDuration: 0.2, animations: {
                v.alpha = 0
                v.transform = CGAffineTransform(translationX: 0, y: -24)
            }, completion: { _ in
                v.removeFromSuperview()
                if self.current === v { self.current = nil }
            })
        }
    }

    /// 弹出面板 / 键盘时 keyWindow 未必是承载内容的那个，退一步找前台场景里的可见窗口
    private static func presentingWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) { return key }
        }
        return scenes.first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { !$0.isHidden })
    }
}
