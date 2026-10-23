import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let win = UIWindow(windowScene: windowScene)
        win.rootViewController = RootTabController()
        win.makeKeyAndVisible()
        self.window = win

        CapabilityRegistry.shared.registerBuiltins()

        // 冷启动时如果是由 URL 唤起，处理它
        if let url = connectionOptions.urlContexts.first?.url {
            handleURL(url)
        }
    }

    /// 热启动时的 URL 唤起
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            handleURL(url)
        }
    }

    /// 解析 kinter://open?appId=xxx&params=json
    private func handleURL(_ url: URL) {
        guard url.scheme == "kinter" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        guard let appId = components.queryItems?.first(where: { $0.name == "appId" })?.value else { return }

        var params: [String: Any]?
        if let ps = components.queryItems?.first(where: { $0.name == "params" })?.value,
           let data = ps.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            params = obj
        }
        // Live Activity 点击时带过来的 deepLink
        if let link = components.queryItems?.first(where: { $0.name == "deepLink" })?.value {
            var merged = params ?? [:]
            merged["_deepLink"] = link
            params = merged
        }

        guard let app = AppLibrary.shared.app(id: appId) else {
            HostPopup.toast("应用未安装")
            return
        }

        // 记录参数，供小程序启动后读取
        MiniAppLauncher.pendingParams[appId] = params ?? [:]

        // 延迟一点，确保 window 已经就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let root = self.window?.rootViewController else { return }
            let runner = MiniAppRunnerController(app: app)
            runner.modalPresentationStyle = .fullScreen
            root.present(runner, animated: true)
        }
    }
}
