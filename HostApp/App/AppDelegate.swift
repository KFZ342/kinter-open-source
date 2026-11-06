import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 预热 WebKit 子进程（GPU / Networking / WebContent），把冷启动开销挪到启动阶段
        MiniAppWebView.prewarm()
        // 安全模式：把拦截事件接到横幅，并把「允许本次 / 以后都允许」落成令牌
        SecurityPresenter.shared.start()
        return true
    }
}
