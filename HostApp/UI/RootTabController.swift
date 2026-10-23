import UIKit

/// 主界面：三个 Tab —— 导入 / 应用库 / 设置。
final class RootTabController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let importVC = ImportViewController()
        importVC.tabBarItem = UITabBarItem(title: "导入",
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
            // 把参数传给应用
            if let params = AppSettings.shared.customParamsDict {
                MiniAppLauncher.pendingParams[app.appId] = params ?? [:]
            }
            MiniAppLauncher.open(app: app, from: self)
        }
    }

}
