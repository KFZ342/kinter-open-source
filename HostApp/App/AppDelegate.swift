import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 后台保活：设置里开启过无声音频保活则自动启动
        KeepAliveAudioPlayer.shared.autoApply()
        return true
    }
}
