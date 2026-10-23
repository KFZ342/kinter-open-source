import UIKit

/// 一个窗口化的迷你应用实例。
/// 标题栏带红绿灯，可拖动、可缩放、可最小化/最大化。
final class AppWindow: UIView {

    let appId: String
    let title: String
    let contentView: UIView

    /// 关闭
    var onClose: (() -> Void)?
    /// 最小化
    var onMinimize: (() -> Void)?
    /// 点击任意位置时置顶
    var onBringToFront: (() -> Void)?
    /// 拖动中，参数是窗口 header 中心点在父视图中的坐标
    var onDragMove: ((CGPoint) -> Void)?
    /// 拖动结束，参数同上
    var onDragEnd: ((CGPoint) -> Void)?
    /// 吸附动画完成后回调
    var onSnapComplete: (() -> Void)?

    private let header = UIView()
    private let titleLabel = UILabel()
    private let resizeHandle = UIView()
    private var savedFrame: CGRect?
    private var isMaximized = false

    private let minSize = CGSize(width: 320, height: 400)
    private let headerHeight: CGFloat = 44
    private let trafficSize: CGFloat = 12

    init(appId: String, title: String, content: UIView) {
        self.appId = appId
        self.title = title
        self.contentView = content
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 6)
        clipsToBounds = false

        // 标题栏
        header.backgroundColor = .secondarySystemBackground
        header.layer.cornerRadius = 12
        header.layer.cornerCurve = .continuous
        header.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        // 红绿灯
        let closeBtn = makeTrafficLight(color: .systemRed, action: #selector(closeTapped))
        let minBtn = makeTrafficLight(color: .systemYellow, action: #selector(minimizeTapped))
        let maxBtn = makeTrafficLight(color: .systemGreen, action: #selector(maximizeTapped))
        let stack = UIStackView(arrangedSubviews: [closeBtn, minBtn, maxBtn])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        // 标题
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        // 拖动
        let pan = UIPanGestureRecognizer(target: self, action: #selector(headerPanned(_:)))
        header.addGestureRecognizer(pan)

        let dbl = UITapGestureRecognizer(target: self, action: #selector(headerDoubleTapped))
        dbl.numberOfTapsRequired = 2
        header.addGestureRecognizer(dbl)

        // 内容区
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        contentView.clipsToBounds = true
        addSubview(contentView)

        // 缩放手柄
        resizeHandle.backgroundColor = .clear
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeHandle)
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(resizePanned(_:)))
        resizeHandle.addGestureRecognizer(resizePan)

        // 显示一条角标线提示可缩放
        let corner = UIView()
        corner.backgroundColor = .tertiaryLabel
        corner.translatesAutoresizingMaskIntoConstraints = false
        corner.transform = CGAffineTransform(rotationAngle: .pi / 4)
        resizeHandle.addSubview(corner)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -14),

            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 20),
            resizeHandle.heightAnchor.constraint(equalToConstant: 20),

            corner.centerXAnchor.constraint(equalTo: resizeHandle.centerXAnchor),
            corner.centerYAnchor.constraint(equalTo: resizeHandle.centerYAnchor),
            corner.widthAnchor.constraint(equalToConstant: 10),
            corner.heightAnchor.constraint(equalToConstant: 2)
        ])

        // 点击置顶
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    private func makeTrafficLight(color: UIColor, action: Selector) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.backgroundColor = color
        btn.layer.cornerRadius = trafficSize / 2
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: trafficSize).isActive = true
        btn.heightAnchor.constraint(equalToConstant: trafficSize).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: - 交互

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func minimizeTapped() {
        onMinimize?()
    }

    @objc func maximizeTapped() {
        guard let superview = superview else { return }
        if isMaximized {
            if let f = savedFrame {
                UIView.animate(withDuration: 0.25) { self.frame = f }
            }
            isMaximized = false
        } else {
            savedFrame = frame
            UIView.animate(withDuration: 0.25) {
                self.frame = superview.bounds
            }
            isMaximized = true
        }
    }

    @objc private func headerDoubleTapped() {
        maximizeTapped()
    }

    @objc private func handleTap() {
        onBringToFront?()
    }

    @objc private func headerPanned(_ g: UIPanGestureRecognizer) {
        guard let superview = superview, !isMaximized else { return }
        let t = g.translation(in: superview)
        var f = frame
        f.origin.x += t.x
        f.origin.y += t.y
        frame = f
        g.setTranslation(.zero, in: superview)
        onBringToFront?()

        let center = CGPoint(x: f.midX, y: f.origin.y + headerHeight / 2)
        switch g.state {
        case .changed:
            onDragMove?(center)
        case .ended, .cancelled:
            onDragEnd?(center)
        default:
            break
        }
    }

    /// 平滑吸附到目标 frame
    func snap(to target: CGRect, animated: Bool = true) {
        savedFrame = nil
        isMaximized = (target == superview?.bounds)
        if animated {
            UIView.animate(withDuration: 0.22,
                           delay: 0,
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0.6) {
                self.frame = target
            } completion: { _ in
                self.onSnapComplete?()
            }
        } else {
            frame = target
            onSnapComplete?()
        }
    }

    /// 双击标题栏最大化 / 恢复
    func toggleMaximize() {
        maximizeTapped()
    }

    @objc private func resizePanned(_ g: UIPanGestureRecognizer) {
        guard let superview = superview, !isMaximized else { return }
        let t = g.translation(in: superview)
        var f = frame
        f.size.width = max(minSize.width, f.size.width + t.x)
        f.size.height = max(minSize.height, f.size.height + t.y)
        frame = f
        g.setTranslation(.zero, in: superview)
    }
}
