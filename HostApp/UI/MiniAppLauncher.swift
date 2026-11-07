import UIKit

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
        ensureVerified(app: app, from: presentingVC) {
            guard let root = presentingVC ?? keyRoot() else { return }
            present(app: app, from: root)
        }
    }

    /// 签名闸门：通过才执行 onPass。
    /// 没签名 / 签名对不上 → 弹「未受验证的开发者，App暂时无法打开」，不启动小程序。
    /// 签名有效但开发者没被信任 → 给一次「信任并打开」的机会。
    static func ensureVerified(app: InstalledApp,
                               from presentingVC: UIViewController?,
                               onPass: @escaping () -> Void) {
        // 宿主自带与 AI 本机生成的应用不需要外部签名
        guard AppSettings.shared.requireDeveloperSignature, !app.isFirstParty else {
            onPass()
            return
        }
        // 算摘要要读整个包，别放主线程
        DispatchQueue.global(qos: .userInitiated).async {
            let status = PackageSignature.status(for: app)
            DispatchQueue.main.async {
                switch status {
                case .unenforced, .firstParty:
                    onPass()
                case .trusted(_):
                    onPass()
                case .untrusted(let developerId, let publicKey, let reviewNote):
                    var text = "「\(app.name)」的签名有效，但开发者 \(developerId) 还没有被这台设备信任。"
                    if let note = reviewNote, !note.isEmpty {
                        text += "\n\n\(note)。"
                    }
                    text += "\n\nApp暂时无法打开。"
                    let alert = UIAlertController(
                        title: "未受验证的开发者",
                        message: text, 
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                    alert.addAction(UIAlertAction(title: "信任并打开", style: .default) { _ in
                        TrustedDevelopers.shared.trust(developerId: developerId,
                                                       publicKey: publicKey)
                        onPass()
                    })
                    present(alert, from: presentingVC)
                case .unsigned:
                    blockedAlert(app: app,
                                 detail: "安装包里没有开发者签名，宿主无法确认它是谁做的。",
                                 from: presentingVC)
                case .invalid(let reason):
                    blockedAlert(app: app,
                                 detail: "签名校验没有通过：\(reason)",
                                 from: presentingVC)
                }
            }
        }
    }

    // MARK: - 内部

    private static func present(app: InstalledApp, from root: UIViewController) {
        let runner = MiniAppRunnerController(app: app)
        runner.modalPresentationStyle = .fullScreen
        root.presentSafely(runner, animated: true)
    }

    private static func blockedAlert(app: InstalledApp, detail: String,
                                     from presentingVC: UIViewController?) {
        let alert = UIAlertController(
            title: "未受验证的开发者",
            message: "App暂时无法打开。\n\n\(detail)\n\n如果这是你自己打包的应用，用 Tools/sign_app.py 签名后再导入。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, from: presentingVC)
    }

    private static func present(_ alert: UIAlertController,
                                from presentingVC: UIViewController?) {
        guard let root = topMost(presentingVC ?? keyRoot()) else { return }
        root.presentSafely(alert, animated: true)
    }

    private static func keyRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
    }

    /// 已经在弹别的页面时，往最上层呈现，避免 "already presenting"
    private static func topMost(_ vc: UIViewController?) -> UIViewController? {
        var cur = vc
        while let presented = cur?.presentedViewController, !presented.isBeingDismissed {
            cur = presented
        }
        return cur
    }
}
