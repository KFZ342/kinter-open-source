import UIKit

/// 多任务工作区。悬浮多个 AppWindow，每个窗口运行一个独立小程序实例。
final class WindowManagerViewController: UIViewController {

    private var windows: [AppWindow] = []
    private var minimized: [AppWindow] = []

    private let toolbar = UIView()
    private let titleLabel = UILabel()
    private let doneBtn = UIButton(type: .system)
    private let addBtn = UIButton(type: .system)
    private let workspace = UIView()
    private let dock = UIView()
    private let dockStack = UIScrollView()
    private let emptyLabel = UILabel()
    /// 吸附预览
    private let snapPreview = UIView()
    /// 当前吸附方向
    /// 布局按钮
    private let layoutBtn = UIButton(type: .system)

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.92, alpha: 1)
        }
        setupUI()
    }

    private func setupUI() {
        // 工具栏
        toolbar.backgroundColor = .secondarySystemBackground
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        doneBtn.setTitle("完成", for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(doneBtn)

        titleLabel.text = "多任务工作区"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(titleLabel)

        addBtn.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        addBtn.tintColor = .systemBlue
        addBtn.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(addBtn)

        // 布局按钮
        layoutBtn.setImage(UIImage(systemName: "rectangle.split.2x1"), for: .normal)
        layoutBtn.tintColor = .systemBlue
        layoutBtn.addTarget(self, action: #selector(layoutTapped), for: .touchUpInside)
        layoutBtn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(layoutBtn)

        // 工作区
        workspace.backgroundColor = .clear
        workspace.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(workspace)

        // 吸附预览层（半透明色块）
        snapPreview.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        snapPreview.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
        snapPreview.layer.borderWidth = 2
        snapPreview.layer.cornerRadius = 12
        snapPreview.isHidden = true
        snapPreview.isUserInteractionEnabled = false
        snapPreview.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(snapPreview)

        // 空状态
        emptyLabel.text = "还没有窗口\n点右上角 + 添加小程序"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(emptyLabel)

        // 底部 dock（最小化窗口）
        dock.backgroundColor = .secondarySystemBackground
        dock.isHidden = true
        dock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dock)

        dockStack.showsHorizontalScrollIndicator = false
        dockStack.translatesAutoresizingMaskIntoConstraints = false
        dock.addSubview(dockStack)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            doneBtn.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            doneBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            layoutBtn.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -8),
            layoutBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            layoutBtn.widthAnchor.constraint(equalToConstant: 32),
            layoutBtn.heightAnchor.constraint(equalToConstant: 32),

            addBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 32),
            addBtn.heightAnchor.constraint(equalToConstant: 32),

            workspace.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            workspace.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            workspace.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            workspace.bottomAnchor.constraint(equalTo: dock.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: workspace.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: workspace.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: workspace.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: workspace.trailingAnchor, constant: -40),

            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dock.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dock.heightAnchor.constraint(equalToConstant: 72),

            dockStack.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 12),
            dockStack.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -12),
            dockStack.centerYAnchor.constraint(equalTo: dock.centerYAnchor),
            dockStack.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    // MARK: - 公开接口

    /// 添加一个应用到工作区。已开则置顶。
    func addApp(_ app: InstalledApp) {
        if let existing = windows.first(where: { $0.appId == app.appId }) {
            bringToFront(existing)
            return
        }

        // 创建 runner
        let runner = MiniAppRunnerController(app: app)
        runner.isMultiTaskChild = true
        addChild(runner)
        runner.didMove(toParent: self)

        // 创建窗口
        let win = AppWindow(appId: app.appId, title: app.name, content: runner.view)
        win.translatesAutoresizingMaskIntoConstraints = true
        win.onClose = { [weak self] in self?.closeWindow(win) }
        win.onMinimize = { [weak self] in self?.minimizeWindow(win) }
        win.onBringToFront = { [weak self] in self?.bringToFront(win) }
        win.onDragMove = { [weak self] c in self?.handleDragMove(center: c) }
        win.onDragEnd = { [weak self] c in self?.handleDragEnd(win: win, center: c) }

        // 初始位置：级联排布
        let count = CGFloat(windows.count)
        let step: CGFloat = 28
        let w: CGFloat = 520
        let h: CGFloat = 640
        let x = 40 + count * step
        let y = 40 + count * step
        win.frame = CGRect(x: x, y: y, width: w, height: h)

        workspace.addSubview(win)
        windows.append(win)
        updateEmptyState()
        bringToFront(win)
    }

    // MARK: - 窗口管理

    private var currentSnap: Int = 0  // 0=none, 1=left, 2=right, 3=top

    private func handleDragMove(center: CGPoint) {
        let w = workspace.bounds.width
        let h = workspace.bounds.height
        var snap = 0
        if center.x < 60 { snap = 1 }
        else if center.x > w - 60 { snap = 2 }
        else if center.y < 50 { snap = 3 }
        guard snap != currentSnap else { return }
        currentSnap = snap

        switch snap {
        case 1: snapPreview.frame = CGRect(x: 8, y: 8, width: w/2-12, height: h-16); snapPreview.isHidden = false
        case 2: snapPreview.frame = CGRect(x: w/2+4, y: 8, width: w/2-12, height: h-16); snapPreview.isHidden = false
        case 3: snapPreview.frame = CGRect(x: 8, y: 8, width: w-16, height: h-16); snapPreview.isHidden = false
        default: snapPreview.isHidden = true
        }
    }

    private func handleDragEnd(win: AppWindow, center: CGPoint) {
        snapPreview.isHidden = true
        let w = workspace.bounds.width
        let h = workspace.bounds.height
        switch currentSnap {
        case 1: win.snap(to: CGRect(x: 8, y: 8, width: w/2-12, height: h-16))
        case 2: win.snap(to: CGRect(x: w/2+4, y: 8, width: w/2-12, height: h-16))
        case 3: win.snap(to: CGRect(x: 8, y: 8, width: w-16, height: h-16))
        default: break
        }
        currentSnap = 0
    }

    private func closeWindow(_ win: AppWindow) {
        // 通知子 runner 清理
        if let idx = children.firstIndex(where: {
            ($0 as? MiniAppRunnerController) != nil
        }) {
            _ = idx
        }
        // 清理所有子 VC 中匹配这个 appId 的
        for child in children {
            if let r = child as? MiniAppRunnerController, r.view === win.contentView {
                r.forceCleanup()
                r.willMove(toParent: nil)
                r.removeFromParent()
            }
        }
        win.removeFromSuperview()
        windows.removeAll { $0 === win }
        minimized.removeAll { $0 === win }
        refreshDock()
        updateEmptyState()
    }

    private func minimizeWindow(_ win: AppWindow) {
        win.isHidden = true
        if !minimized.contains(where: { $0 === win }) {
            minimized.append(win)
        }
        refreshDock()
    }

    private func restoreWindow(_ win: AppWindow) {
        win.isHidden = false
        minimized.removeAll { $0 === win }
        refreshDock()
        bringToFront(win)
    }

    private func bringToFront(_ win: AppWindow) {
        workspace.bringSubviewToFront(win)
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !windows.isEmpty
    }

    private func refreshDock() {
        dock.isHidden = minimized.isEmpty
        dockStack.subviews.forEach { $0.removeFromSuperview() }

        var x: CGFloat = 0
        for win in minimized {
            let btn = UIButton(type: .system)
            btn.setTitle(win.title, for: .normal)
            btn.setImage(UIImage(systemName: "rectangle.on.rectangle"), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.backgroundColor = .systemBackground
            btn.layer.cornerRadius = 8
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            btn.frame = CGRect(x: x, y: 6, width: 160, height: 40)
            btn.addAction(UIAction { [weak self] _ in
                self?.restoreWindow(win)
            }, for: .touchUpInside)
            dockStack.addSubview(btn)
            x += 168
        }
        dockStack.contentSize = CGSize(width: max(x, dockStack.bounds.width), height: 52)
    }

    // MARK: - 事件

    @objc private func layoutTapped() {
        guard !windows.isEmpty else { HostPopup.toast("先添加窗口"); return }
        let a = UIAlertController(title: "布局", message: nil, preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "双栏", style: .default) { [weak self] _ in self?.applyLayout(2) })
        a.addAction(UIAlertAction(title: "三栏", style: .default) { [weak self] _ in self?.applyLayout(3) })
        a.addAction(UIAlertAction(title: "2x2 网格", style: .default) { [weak self] _ in self?.applyLayout(4) })
        a.addAction(UIAlertAction(title: "全部最大化", style: .default) { [weak self] _ in self?.applyLayout(0) })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let p = a.popoverPresentationController { p.sourceView = view; p.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) }
        present(a, animated: true)
    }

    private func applyLayout(_ n: Int) {
        let vis = windows.filter { !$0.isHidden }
        let w = workspace.bounds.width, h = workspace.bounds.height, g: CGFloat = 8
        if n == 0 {
            for win in vis { win.snap(to: CGRect(x: g, y: g, width: w-g*2, height: h-g*2)) }
            return
        }
        if n == 2 {
            for (i, win) in vis.prefix(2).enumerated() {
                let x = i == 0 ? g : w/2 + g/2
                win.snap(to: CGRect(x: x, y: g, width: w/2-g*1.5, height: h-g*2))
            }
            return
        }
        if n == 3 {
            let cw = (w - g*4) / 3
            for (i, win) in vis.prefix(3).enumerated() {
                win.snap(to: CGRect(x: g + CGFloat(i)*(cw+g), y: g, width: cw, height: h-g*2))
            }
            return
        }
        if n == 4 {
            let cw = w/2-g*1.5, ch = h/2-g*1.5
            for (i, win) in vis.prefix(4).enumerated() {
                let x = g + CGFloat(i % 2)*(cw+g)
                let y = g + CGFloat(i / 2)*(ch+g)
                win.snap(to: CGRect(x: x, y: y, width: cw, height: ch))
            }
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(kbClose)),
            UIKeyCommand(input: "m", modifierFlags: .command, action: #selector(kbMin)),
            UIKeyCommand(input: "1", modifierFlags: .command, action: #selector(kbWin1)),
            UIKeyCommand(input: "2", modifierFlags: .command, action: #selector(kbWin2)),
            UIKeyCommand(input: "3", modifierFlags: .command, action: #selector(kbWin3)),
            UIKeyCommand(input: "4", modifierFlags: .command, action: #selector(kbWin4))
        ]
    }

    @objc private func kbClose() { if let w = windows.last(where: { !$0.isHidden }) { closeWindow(w) } }
    @objc private func kbMin() { if let w = windows.last(where: { !$0.isHidden }) { minimizeWindow(w) } }
    @objc private func kbWin1() { switchTo(0) }
    @objc private func kbWin2() { switchTo(1) }
    @objc private func kbWin3() { switchTo(2) }
    @objc private func kbWin4() { switchTo(3) }

    private func switchTo(_ idx: Int) {
        guard idx < windows.count else { return }
        let w = windows[idx]
        if w.isHidden { restoreWindow(w) } else { bringToFront(w) }
    }

    @objc private func doneTapped() {
        // 关闭整个工作区
        for child in children {
            (child as? MiniAppRunnerController)?.forceCleanup()
        }
        dismiss(animated: true)
    }

    @objc private func addTapped() {
        let picker = AppPickerViewController()
        picker.onPick = { [weak self] app in
            self?.addApp(app)
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
}
