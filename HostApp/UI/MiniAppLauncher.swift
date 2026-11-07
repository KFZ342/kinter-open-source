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
                case .verified(let developerId, let reviewNote):
                    if let note = reviewNote {
                        NSLog("[Signature] \(app.name) 已验证：\(developerId)；\(note)")
                    }
                    onPass()
                case .trusted(_):
                    onPass()
                case .selfSigned(let developerId, let publicKey):
                    // 自签名只在开发模式里给一次机会；正式模式直接挡
                    handleSelfSigned(app: app, developerId: developerId,
                                      publicKey: publicKey,
                                      from: presentingVC, onPass: onPass)
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

    private static func handleSelfSigned(app: InstalledApp,
                                          developerId: String,
                                          publicKey: String,
                                          from presentingVC: UIViewController?,
                                          onPass: @escaping () -> Void) {
        guard AppSettings.shared.allowSelfSignedApps else {
            blockedAlert(app: app,
                         detail: "签名有效，但没有可信根证书签发。签名只能证明包没被换过，证明不了开发者是谁。",
                         from: presentingVC)
            return
        }
        guard !TrustedDevelopers.shared.isTrusted(developerId: developerId,
                                                  publicKey: publicKey) else {
            onPass()
            return
        }
        let alert = UIAlertController(
            title: "开发模式：未受验证的开发者",
            message: "「\(app.name)」是自签名包，开发者 \(developerId) 没有根证书。\n\n当前开着开发模式，可以手动信任这一把公钥。正式分发请关掉。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "信任并打开", style: .default) { _ in
            TrustedDevelopers.shared.trust(developerId: developerId, publicKey: publicKey)
            onPass()
        })
        present(alert, from: presentingVC)
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
