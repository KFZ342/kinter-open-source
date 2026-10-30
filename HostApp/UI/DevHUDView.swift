import UIKit

/// 独家：宿主级性能监视浮层（DevHUD）。
///
/// 微信/支付宝开发者工具的性能面板只存在于桌面 IDE；Kinter 把性能监视
/// 直接做进宿主运行界面，C 端用户和开发者都能实时看到当前小程序会话的：
/// FPS、桥接调用次数/失败、JS 错误数、运行时长、联动窗口会话数。
final class DevHUDView: UIView {
    private let fpsLabel = UILabel()
    private let bridgeLabel = UILabel()
    private let jsLabel = UILabel()
    private let uptimeLabel = UILabel()
    private let sessionLabel = UILabel()

    private var displayLink: CADisplayLink?
    private var frameCount = 0
    private var lastTickTime: CFTimeInterval = 0
    private var currentFPS: Double = 0
    private let startedAt = Date()

    /// 桥接统计数据源（Runner 注入：读取 BridgeMessageHandler 计数）
    var bridgeStats: (() -> (calls: Int, errors: Int))?
    /// JS 错误累计（Runner 注入：onJavascriptLog 的 error 计数）
    var jsErrorCount: (() -> Int)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.07, alpha: 0.88)
        layer.cornerRadius = 10
        layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        layer.borderWidth = 1

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        fpsLabel.textColor = .systemGreen
        fpsLabel.text = "FPS --"
        bridgeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        bridgeLabel.textColor = .white
        bridgeLabel.text = "桥接 --"
        jsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        jsLabel.textColor = .systemOrange
        jsLabel.text = "JS 错误 0"
        sessionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sessionLabel.textColor = .systemBlue
        sessionLabel.text = "联动窗口 --"
        uptimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        uptimeLabel.textColor = .systemGray
        uptimeLabel.text = "运行 00:00"

        stack.addArrangedSubview(fpsLabel)
        stack.addArrangedSubview(bridgeLabel)
        stack.addArrangedSubview(jsLabel)
        stack.addArrangedSubview(sessionLabel)
        stack.addArrangedSubview(uptimeLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 168)
        ])

        let link = CADisplayLink(target: self, selector: #selector(linkTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTickTime = link.timestamp
        refreshStats()
    }

    @objc private func linkTick() {
        frameCount += 1
        let now = displayLink?.timestamp ?? CACurrentMediaTime()
        let elapsed = now - lastTickTime
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastTickTime = now
            refreshStats()
        }
    }

    private func refreshStats() {
        fpsLabel.text = String(format: "FPS %.0f  %@", currentFPS,
                               currentFPS >= 55 ? "流畅" : (currentFPS >= 30 ? "可接受" : "卡顿"))
        fpsLabel.textColor = currentFPS >= 55 ? .systemGreen : (currentFPS >= 30 ? .systemYellow : .systemRed)

        if let stats = bridgeStats?() {
            bridgeLabel.text = "桥接 \(stats.calls) 次 · 失败 \(stats.errors)"
            bridgeLabel.textColor = stats.errors > 0 ? .systemOrange : .white
        } else {
            bridgeLabel.text = "桥接 --"
        }
        jsLabel.text = "JS 错误 \(jsErrorCount?() ?? 0)"

        let active = HostSharedBus.shared.sessionCount
        sessionLabel.text = "联动窗口 \(active) 个在线"

        let t = Date().timeIntervalSince(startedAt)
        uptimeLabel.text = String(format: "运行 %02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
