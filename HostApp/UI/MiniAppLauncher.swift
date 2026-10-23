import UIKit

/// 小程序启动入口：模态全屏呈现。
enum MiniAppLauncher {

    /// 待注入的启动参数，按 appId 索引。
    /// Runner 创建时读取并清空。
    static var pendingParams: [String: [String: Any]] = [:]

    static func takeParams(for appId: String) -> [String: Any]? {
        let p = pendingParams[appId]
        pendingParams.removeValue(forKey: appId)
        return p
    }

    static func open(app: InstalledApp, from presentingVC: UIViewController? = nil) {
        let source = presentingVC
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                .first
        guard let root = source else { return }

        let runner = MiniAppRunnerController(app: app)
        runner.modalPresentationStyle = .fullScreen
        root.present(runner, animated: true)
    }
}
