import UIKit

/// Web 控制横幅：悬浮在 App 最上层，实时显示"浏览器那边正在干什么"，并允许一键踢出。
///
/// 为什么放在 window 上而不是某个页面里：
/// - 用户可能正在 App 里跑别的小程序，Web 端同时在操作，横幅必须始终可见；
/// - 放在 window 上不受 tab / 导航控制器层级影响，收起时也不占布局。
final class WebControlBanner: UIView, UIGestureRecognizerDelegate {

    static let shared = WebControlBanner()

    /// 只按"真实操作"计时；控制台的 /api/poll 轮询不算，否则页面开着横幅就永远不消失
    private static let activityWindow: TimeInterval = 25

    private weak var hostWindow: UIWindow?
    private var refreshTimer: Timer?
    private var isVisible = false
    private var showingLoggedOut = false

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let dot = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let kickButton = UIButton(type: .system)

    private init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 安装

    func install(in window: UIWindow) {
        if hostWindow === window { return }
        // 重复安装（窗口重建）：先从旧父视图剥离，避免横幅挂在已释放的窗口上。
        removeFromSuperview()
        hostWindow = window
        window.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false

        // iPad 的 Tab 栏在顶部，横幅下移一行避免压住标签；iPhone 从安全区顶部开始
        let topInset: CGFloat = window.traitCollection.userInterfaceIdiom == .pad ? 58 : 8

        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: topInset),
            centerXAnchor.constraint(equalTo: window.centerXAnchor),
            leadingAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            trailingAnchor.constraint(lessThanOrEqualTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        ])

        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -24)

        WebAccessService.shared.onActivityChange = { [weak self] _ in
            self?.refresh(animated: true)
        }

        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh(animated: false)
        }
        // 加入 common mode：底层页面滚动时定时器不被暂停，活动超时隐藏仍然准时。
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh(animated: false)
    }

    // MARK: - 视图

    private func setup() {
        backgroundColor = .clear
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        addSubview(blurView)

        // 左侧脉冲小圆点
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = .systemBlue
        dot.layer.cornerRadius = 4
        dot.layer.shadowColor = UIColor.systemBlue.cgColor
        dot.layer.shadowOpacity = 0.6
        dot.layer.shadowRadius = 5
        dot.layer.shadowOffset = .zero

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.text = "Web 端正在控制这台设备"

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabel
        detailLabel.lineBreakMode = .byTruncatingTail

        kickButton.translatesAutoresizingMaskIntoConstraints = false
        kickButton.setTitle("踢出", for: .normal)
        kickButton.setTitleColor(.systemRed, for: .normal)
        kickButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        kickButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        kickButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        kickButton.layer.cornerRadius = 11
        kickButton.layer.cornerCurve = .continuous
        kickButton.addTarget(self, action: #selector(kickTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [dot, textStack, kickButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        // 注意：不能关闭 stack 的交互。UIKit 命中测试在父视图 isUserInteractionEnabled=false 时
        // 直接返回 nil，不再下钻子视图，kickButton 会因此完全点不动。
        stack.isUserInteractionEnabled = true
        blurView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            stack.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -9),
            stack.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -10),

            kickButton.heightAnchor.constraint(equalToConstant: 26)
        ])

        kickButton.isUserInteractionEnabled = true
        kickButton.isAccessibilityElement = true
        kickButton.accessibilityLabel = "踢出 Web 控制"
        let tap = UITapGestureRecognizer(target: self, action: #selector(openPanel))
        tap.delegate = self
        addGestureRecognizer(tap)

        // 横幅作为容器，标题与按钮分别成为可聚焦元素，VoiceOver 才能单独操作「踢出」。
        isAccessibilityElement = false
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityLabel = "Web 端正在控制，点按查看 Web 端访问设置"
    }

    // MARK: - 命中测试

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 隐藏（alpha 接近 0）时直接透传，不遮挡底层内容。
        guard isVisible, alpha > 0.01 else { return nil }
        // 按钮区域优先命中；其余横幅区域走默认命中（保留打开设置的点按手势）。
        let buttonPoint = convert(point, to: kickButton)
        if kickButton.point(inside: buttonPoint, with: event) {
            return kickButton
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - 刷新

    private func refresh(animated: Bool) {
        let service = WebAccessService.shared

        // 注销后的"已退出"提示要一直留到用户点 ×，不受活动超时影响
        if service.isRunning, service.webLoggedOut {
            applyExitStyle()
            titleLabel.text = "Web 端已退出"
            detailLabel.text = "令牌已更换，旧链接已失效"
            setVisible(true, animated: animated)
            return
        }

        applyNormalStyle()
        guard service.isRunning,
              let activity = service.webActivity,
              Date().timeIntervalSince(activity.at) < Self.activityWindow else {
            setVisible(false, animated: animated)
            return
        }

        titleLabel.text = activity.label
        detailLabel.text = "Web 端操作 · \(relativeText(activity.at))"
        setVisible(true, animated: animated)
    }

    private func applyExitStyle() {
        guard !showingLoggedOut else { return }
        showingLoggedOut = true
        kickButton.setTitle("×", for: .normal)
        kickButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        kickButton.setTitleColor(.secondaryLabel, for: .normal)
        kickButton.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.12)
        dot.backgroundColor = .systemGray
        dot.layer.shadowColor = UIColor.systemGray.cgColor
    }

    private func applyNormalStyle() {
        guard showingLoggedOut else { return }
        showingLoggedOut = false
        kickButton.setTitle("踢出", for: .normal)
        kickButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        kickButton.setTitleColor(.systemRed, for: .normal)
        kickButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        dot.backgroundColor = .systemBlue
        dot.layer.shadowColor = UIColor.systemBlue.cgColor
    }

    private func relativeText(_ date: Date) -> String {
        let seconds = Int(max(0, Date().timeIntervalSince(date)))
        if seconds < 3 { return "刚刚" }
        if seconds < 60 { return "\(seconds) 秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        return "\(minutes / 60) 小时前"
    }

    private func setVisible(_ visible: Bool, animated: Bool) {
        guard visible != isVisible else {
            if visible { updateDotPulse() }
            return
        }
        isVisible = visible

        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: -24)
        }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.85,
                           initialSpringVelocity: 0.4, options: [.curveEaseOut],
                           animations: changes)
        } else {
            changes()
        }
        updateDotPulse()
    }

    private func updateDotPulse() {
        guard isVisible else {
            dot.layer.removeAnimation(forKey: "pulse")
            return
        }
        guard dot.layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer.add(pulse, forKey: "pulse")
    }

    // MARK: - 交互

    @objc private func kickTapped() {
        if WebAccessService.shared.webLoggedOut {
            // 已经是"已退出"提示：这个按钮变成关闭
            WebAccessService.shared.dismissLoggedOutNotice()
            setVisible(false, animated: true)
            return
        }
        WebAccessService.shared.kickWebControl()
        setVisible(false, animated: true)
        HostPopup.toast("已踢出 Web 控制，旧链接立即失效")
    }

    /// 点 × 时不要顺手触发横幅本体的"打开设置"
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current === kickButton { return false }
            view = current.superview
        }
        return true
    }

    @objc private func openPanel() {
        guard let root = hostWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        guard !(top is WebAccessViewController) else { return }
        let nav = UINavigationController(rootViewController: WebAccessViewController())
        nav.modalPresentationStyle = .formSheet
        top.present(nav, animated: true)
    }
}
