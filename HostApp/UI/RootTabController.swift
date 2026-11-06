import UIKit

/// 主界面：三个 Tab —— 导入 / 应用库 / 设置。
final class RootTabController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // 使用原生的 UITabBarAppearance 配置液态玻璃质感
        let appearance = UITabBarAppearance()
        
        // 允许系统原生的模糊效果（毛玻璃）透出底层内容
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        
        // 设置选中和未选中的颜色
        appearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        appearance.stackedLayoutAppearance.selected.iconColor = .systemBlue
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
        
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance

        // 让整个控制器的背景透明，以便系统层级的模糊效果生效
        view.backgroundColor = .clear

        let importVC = ImportViewController()
        importVC.tabBarItem = UITabBarItem(title: "导入应用",
                                           image: UIImage(systemName: "square.and.arrow.down"),
                                           tag: 0)

        let libraryVC = LibraryViewController()
        libraryVC.tabBarItem = UITabBarItem(title: "应用库",
                                            image: UIImage(systemName: "square.grid.2x2"),
                                            tag: 1)

        let storeVC = StoreViewController()
        storeVC.tabBarItem = UITabBarItem(title: "商店",
                                          image: UIImage(systemName: "bag"),
                                          tag: 2)

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(title: "设置",
                                             image: UIImage(systemName: "gearshape"),
                                             tag: 3)

        viewControllers = [
            UINavigationController(rootViewController: importVC),
            UINavigationController(rootViewController: libraryVC),
            UINavigationController(rootViewController: storeVC),
            UINavigationController(rootViewController: settingsVC)
        ]
        
        // 监听深色/浅色模式变化以刷新玻璃材质
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            self.tabBar.setNeedsLayout()
        }
    }

    private var hasHandledLaunch = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasHandledLaunch else { return }
        hasHandledLaunch = true

        let mode = AppSettings.shared.launchMode
        switch mode {
        case .normal:
            break
        case .library:
            selectedIndex = 1
        case .lastApp:
            if let appId = AppSettings.shared.lastOpenedAppId,
               let app = AppLibrary.shared.app(id: appId) {
                MiniAppLauncher.open(app: app, from: self)
            }
        case .custom:
            guard let appId = AppSettings.shared.customAppId,
                  let app = AppLibrary.shared.app(id: appId) else {
                HostPopup.toast("定制启动的应用未安装")
                break
            }
            if let params = AppSettings.shared.customParamsDict {
                MiniAppLauncher.pendingParams[app.appId] = params ?? [:]
            }
            MiniAppLauncher.open(app: app, from: self)
        }
    }
}
