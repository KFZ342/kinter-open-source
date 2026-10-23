import UIKit

/// 多任务容器：同一个应用的多个独立实例，用顶部标签切换。
final class MultiTaskContainerController: UIViewController {

    private let app: InstalledApp
    private let instanceCount: Int
    private var runners: [MiniAppRunnerController] = []
    private var currentIndex: Int = 0

    private let tabBar = UIScrollView()
    private let tabStack = UIStackView()
    private let contentView = UIView()

    init(app: InstalledApp, count: Int) {
        self.app = app
        self.instanceCount = max(1, count)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        createRunners()
    }

    private func setupUI() {
        // 顶部标签栏
        tabBar.backgroundColor = .secondarySystemBackground
        tabBar.showsHorizontalScrollIndicator = false
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)

        tabStack.axis = .horizontal
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tabStack)

        // 内容区
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 52),

            tabStack.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 12),
            tabStack.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -12),
            tabStack.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabStack.heightAnchor.constraint(equalToConstant: 40),

            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func createRunners() {
        for i in 0..<instanceCount {
            let runner = MiniAppRunnerController(app: app)
            runner.isMultiTaskChild = true
            addChild(runner)
            runners.append(runner)
            runner.didMove(toParent: self)

            // 添加到 tab
            let tab = makeTab(index: i)
            tabStack.addArrangedSubview(tab)
        }
        showInstance(at: 0)
    }

    private func makeTab(index: Int) -> UIView {
        let container = UIView()
        container.backgroundColor = index == 0 ? .systemBackground : .clear
        container.layer.cornerRadius = 10
        container.layer.cornerCurve = .continuous
        container.tag = index
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "实例 \(index + 1)"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = .secondaryLabel
        closeBtn.tag = index
        closeBtn.addTarget(self, action: #selector(closeInstance(_:)), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(closeBtn)

        // 点击切到本实例
        let tap = UITapGestureRecognizer(target: self, action: #selector(tabTapped(_:)))
        container.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 40),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            closeBtn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            closeBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            closeBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 20),
            closeBtn.heightAnchor.constraint(equalToConstant: 20)
        ])

        return container
    }

    @objc private func tabTapped(_ gesture: UITapGestureRecognizer) {
        guard let idx = gesture.view?.tag else { return }
        showInstance(at: idx)
    }

    @objc private func closeInstance(_ sender: UIButton) {
        let idx = sender.tag
        guard idx < runners.count else { return }

        // 只剩一个就关掉整个容器
        if runners.count == 1 {
            dismiss(animated: true)
            return
        }

        let runner = runners[idx]
        runner.willMove(toParent: nil)
        runner.view.removeFromSuperview()
        runner.removeFromParent()
        runners.remove(at: idx)

        // 移除 tab
        if idx < tabStack.arrangedSubviews.count {
            let v = tabStack.arrangedSubviews[idx]
            tabStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        // 重编号 tag
        for (i, view) in tabStack.arrangedSubviews.enumerated() {
            view.tag = i
            if let label = view.subviews.compactMap({ $0 as? UILabel }).first {
                label.text = "实例 \(i + 1)"
            }
            if let btn = view.subviews.compactMap({ $0 as? UIButton }).first {
                btn.tag = i
            }
        }

        if currentIndex >= runners.count {
            currentIndex = runners.count - 1
        }
        showInstance(at: currentIndex)
    }

    private func showInstance(at index: Int) {
        guard index < runners.count else { return }
        currentIndex = index

        // 移除所有 runner 的 view
        for (i, r) in runners.enumerated() {
            if i != index {
                r.view.removeFromSuperview()
            }
        }

        let runner = runners[index]
        if runner.view.superview == nil {
            runner.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(runner.view)
            NSLayoutConstraint.activate([
                runner.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                runner.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                runner.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                runner.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        // 更新 tab 高亮
        for (i, view) in tabStack.arrangedSubviews.enumerated() {
            view.backgroundColor = i == index ? .systemBackground : .clear
        }
    }

    /// 整个容器关闭时，通知所有 runner 清理
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            for r in runners {
                r.forceCleanup()
            }
        }
    }
}
