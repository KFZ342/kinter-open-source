import UIKit

/// 宿主自绘弹窗系统。不使用 UIAlertController，视觉与交互完全可控。
/// 三种形态：Toast（短暂提示）、Modal（确认框）、ActionSheet（底部选项）。
/// 全部挂在当前 keyWindow 上，盖在 WebView 之上，跨页面保留。
final class HostPopup {

    static let shared = HostPopup()
    private init() {}

    // MARK: - 公共入口

    /// 短暂提示。
    static func toast(_ text: String, duration: TimeInterval = 1.8) {
        DispatchQueue.main.async {
            shared.showToast(text, duration: duration)
        }
    }

    /// 确认框。completion 返回 true 表示点了确认。
    static func modal(title: String,
                      content: String,
                      confirmText: String = "确定",
                      cancelText: String? = "取消",
                      completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            shared.showModal(title: title,
                             content: content,
                             confirmText: confirmText,
                             cancelText: cancelText,
                             completion: completion)
        }
    }

    /// 底部选项。completion 返回点击的索引，取消为 nil。
    static func actionSheet(items: [String],
                            title: String? = nil,
                            cancelText: String = "取消",
                            completion: @escaping (Int?) -> Void) {
        DispatchQueue.main.async {
            shared.showActionSheet(items: items,
                                   title: title,
                                   cancelText: cancelText,
                                   completion: completion)
        }
    }

    // MARK: - 内部状态

    private var currentToast: UIView?
    private var toastQueue: [(String, TimeInterval)] = []
    private var isShowingToast = false
    private var currentOverlay: UIView?

    /// 当前可用的 keyWindow。
    private var hostWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }

    // MARK: - Toast

    private func showToast(_ text: String, duration: TimeInterval) {
        toastQueue.append((text, duration))
        drainToastQueue()
    }

    private func drainToastQueue() {
        guard !isShowingToast, let window = hostWindow, !toastQueue.isEmpty else { return }
        isShowingToast = true
        let (text, duration) = toastQueue.removeFirst()

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.95, alpha: 0.95)
                : UIColor(white: 0.1, alpha: 0.88)
        }
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous
        container.alpha = 0
        container.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? .black : .white
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        window.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -40),
            container.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, multiplier: 0.7),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])

        currentToast = container

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            container.alpha = 1
            container.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.22,
                           delay: duration,
                           options: [.curveEaseIn]) {
                container.alpha = 0
                container.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            } completion: { _ in
                container.removeFromSuperview()
                self.currentToast = nil
                self.isShowingToast = false
                self.drainToastQueue()
            }
        }
    }

    // MARK: - Modal

    private func showModal(title: String,
                           content: String,
                           confirmText: String,
                           cancelText: String?,
                           completion: @escaping (Bool) -> Void) {
        guard let window = hostWindow else { completion(false); return }
        dismissCurrentOverlay()

        // 遮罩
        let overlay = UIView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        overlay.alpha = 0
        window.addSubview(overlay)
        currentOverlay = overlay

        // 卡片
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        overlay.addSubview(card)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label

        let contentLabel = UILabel()
        contentLabel.text = content
        contentLabel.font = .systemFont(ofSize: 14)
        contentLabel.textAlignment = .center
        contentLabel.numberOfLines = 0
        contentLabel.textColor = .secondaryLabel

        let textStack = UIStackView(arrangedSubviews: [titleLabel, contentLabel])
        textStack.axis = .vertical
        textStack.spacing = 8
        textStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textStack)

        // 按钮行（手动约束，避免 UIStackView 的 fillEqually 把分隔线拉宽）
        let buttonRow = UIView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        // 顶部分隔线
        let topDivider = UIView()
        topDivider.backgroundColor = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(topDivider)

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle(cancelText, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: cancelText == nil ? .semibold : .regular)
        cancelBtn.setTitleColor(cancelText == nil ? .systemBlue : .secondaryLabel, for: .normal)
        cancelBtn.addTarget(self, action: #selector(modalCancelTapped), for: .touchUpInside)

        let confirmBtn = UIButton(type: .system)
        confirmBtn.setTitle(confirmText, for: .normal)
        confirmBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        confirmBtn.setTitleColor(.systemBlue, for: .normal)
        confirmBtn.addTarget(self, action: #selector(modalConfirmTapped), for: .touchUpInside)

        // 存闭包
        modalCompletion = completion

        if let _ = cancelText {
            cancelBtn.translatesAutoresizingMaskIntoConstraints = false
            confirmBtn.translatesAutoresizingMaskIntoConstraints = false
            buttonRow.addSubview(cancelBtn)
            buttonRow.addSubview(confirmBtn)

            let vertDivider = UIView()
            vertDivider.backgroundColor = .separator
            vertDivider.translatesAutoresizingMaskIntoConstraints = false
            buttonRow.addSubview(vertDivider)

            NSLayoutConstraint.activate([
                cancelBtn.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
                cancelBtn.topAnchor.constraint(equalTo: buttonRow.topAnchor),
                cancelBtn.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),

                vertDivider.leadingAnchor.constraint(equalTo: cancelBtn.trailingAnchor),
                vertDivider.topAnchor.constraint(equalTo: buttonRow.topAnchor),
                vertDivider.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
                vertDivider.widthAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

                confirmBtn.leadingAnchor.constraint(equalTo: vertDivider.trailingAnchor),
                confirmBtn.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
                confirmBtn.topAnchor.constraint(equalTo: buttonRow.topAnchor),
                confirmBtn.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),

                // 两个按钮等宽
                cancelBtn.widthAnchor.constraint(equalTo: confirmBtn.widthAnchor)
            ])
        } else {
            confirmBtn.translatesAutoresizingMaskIntoConstraints = false
            buttonRow.addSubview(confirmBtn)
            NSLayoutConstraint.activate([
                confirmBtn.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
                confirmBtn.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
                confirmBtn.topAnchor.constraint(equalTo: buttonRow.topAnchor),
                confirmBtn.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor)
            ])
        }

        card.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 300),

            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            textStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            textStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            topDivider.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 20),
            topDivider.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            buttonRow.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            buttonRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            buttonRow.heightAnchor.constraint(equalToConstant: 50)
        ])

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            overlay.alpha = 1
            card.transform = .identity
        }
    }

    private var modalCompletion: ((Bool) -> Void)?

    @objc private func modalConfirmTapped() {
        let c = modalCompletion
        modalCompletion = nil
        dismissCurrentOverlay {
            c?(true)
        }
    }

    @objc private func modalCancelTapped() {
        let c = modalCompletion
        modalCompletion = nil
        dismissCurrentOverlay {
            c?(false)
        }
    }

    // MARK: - ActionSheet

    private func showActionSheet(items: [String],
                                 title: String?,
                                 cancelText: String,
                                 completion: @escaping (Int?) -> Void) {
        guard let window = hostWindow, !items.isEmpty else { completion(nil); return }
        dismissCurrentOverlay()

        actionSheetCompletion = completion

        let overlay = UIView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        overlay.alpha = 0
        window.addSubview(overlay)
        currentOverlay = overlay

        let tap = UITapGestureRecognizer(target: self, action: #selector(actionSheetCancelTapped))
        overlay.addGestureRecognizer(tap)

        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(container)

        // 选项卡片
        let optionsCard = UIView()
        optionsCard.backgroundColor = .secondarySystemGroupedBackground
        optionsCard.layer.cornerRadius = 14
        optionsCard.layer.cornerCurve = .continuous

        let optionsStack = UIStackView()
        optionsStack.axis = .vertical
        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        optionsCard.addSubview(optionsStack)

        // 标题
        if let title = title, !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 13)
            titleLabel.textColor = .secondaryLabel
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            let wrapper = UIView()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 14),
                titleLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14),
                titleLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
                titleLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20)
            ])
            optionsStack.addArrangedSubview(wrapper)
            optionsStack.addArrangedSubview(makeDivider())
        }

        // 选项
        for (i, item) in items.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(item, for: .normal)
            btn.setTitleColor(.systemBlue, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 18)
            btn.tag = i
            btn.addTarget(self, action: #selector(actionSheetItemTapped(_:)), for: .touchUpInside)
            btn.heightAnchor.constraint(equalToConstant: 56).isActive = true
            optionsStack.addArrangedSubview(btn)
            if i < items.count - 1 {
                optionsStack.addArrangedSubview(makeDivider())
            }
        }

        NSLayoutConstraint.activate([
            optionsStack.topAnchor.constraint(equalTo: optionsCard.topAnchor),
            optionsStack.bottomAnchor.constraint(equalTo: optionsCard.bottomAnchor),
            optionsStack.leadingAnchor.constraint(equalTo: optionsCard.leadingAnchor),
            optionsStack.trailingAnchor.constraint(equalTo: optionsCard.trailingAnchor)
        ])

        container.addArrangedSubview(optionsCard)

        // 取消按钮
        let cancelCard = UIView()
        cancelCard.backgroundColor = .secondarySystemGroupedBackground
        cancelCard.layer.cornerRadius = 14
        cancelCard.layer.cornerCurve = .continuous
        cancelCard.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle(cancelText, for: .normal)
        cancelBtn.setTitleColor(.systemBlue, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        cancelBtn.addTarget(self, action: #selector(actionSheetCancelTapped), for: .touchUpInside)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelCard.addSubview(cancelBtn)
        NSLayoutConstraint.activate([
            cancelBtn.topAnchor.constraint(equalTo: cancelCard.topAnchor),
            cancelBtn.bottomAnchor.constraint(equalTo: cancelCard.bottomAnchor),
            cancelBtn.leadingAnchor.constraint(equalTo: cancelCard.leadingAnchor),
            cancelBtn.trailingAnchor.constraint(equalTo: cancelCard.trailingAnchor)
        ])
        container.addArrangedSubview(cancelCard)

        let safeBottom = window.safeAreaInsets.bottom
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            container.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -safeBottom - 8)
        ])

        // 入场：从底部滑入
        container.transform = CGAffineTransform(translationX: 0, y: 400)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            overlay.alpha = 1
            container.transform = .identity
        }
    }

    private var actionSheetCompletion: ((Int?) -> Void)?

    @objc private func actionSheetItemTapped(_ sender: UIButton) {
        let c = actionSheetCompletion
        actionSheetCompletion = nil
        dismissCurrentOverlay {
            c?(sender.tag)
        }
    }

    @objc private func actionSheetCancelTapped() {
        let c = actionSheetCompletion
        actionSheetCompletion = nil
        dismissCurrentOverlay {
            c?(nil)
        }
    }

    // MARK: - 工具

    private func makeDivider() -> UIView {
        let d = UIView()
        d.backgroundColor = .separator
        d.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return d
    }

    private func dismissCurrentOverlay(completion: (() -> Void)? = nil) {
        guard let overlay = currentOverlay else {
            completion?()
            return
        }
        currentOverlay = nil
        UIView.animate(withDuration: 0.18) {
            overlay.alpha = 0
        } completion: { _ in
            overlay.removeFromSuperview()
            completion?()
        }
    }

    // MARK: - 清理

    /// 关闭所有弹窗并清空队列。小程序关闭时调用，避免残留。
    static func dismissAll() {
        DispatchQueue.main.async {
            shared.dismissAllInternal()
        }
    }

    private func dismissAllInternal() {
        toastQueue.removeAll()
        isShowingToast = false
        currentToast?.removeFromSuperview()
        currentToast = nil

        modalCompletion = nil
        actionSheetCompletion = nil

        currentOverlay?.removeFromSuperview()
        currentOverlay = nil
    }
}
