import Foundation
import UIKit

/// 把「能力被拦截」事件接到横幅上，并把用户在横幅上的选择落成令牌/信任。
///
/// 之前 SecurityBanner 只是画好了 UI，没有任何地方 show 它，
/// OneShotGrant.grant 也没有调用点 —— 结果是安全模式只会拒绝，用户没有任何放行入口。
/// 这一层就是补上那段接线。
final class SecurityPresenter {
    static let shared = SecurityPresenter()
    private init() {}

    /// 同一 (appId, 能力) 在这个窗口内只提示一次，避免轮询类调用把横幅刷成弹幕
    private let debounce: TimeInterval = 3
    private var lastShown: [String: Date] = [:]
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .securityCapabilityBlocked,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, let ev = note.object as? SecurityEvent else { return }
            self.present(ev)
        }
    }

    private func present(_ ev: SecurityEvent) {
        let key = "\(ev.appId ?? "-")::\(ev.grantKey)"
        let now = Date()

        lock.lock()
        if let last = lastShown[key], now.timeIntervalSince(last) < debounce {
            lock.unlock()
            return
        }
        lastShown[key] = now
        if lastShown.count > 128 {
            lastShown = lastShown.filter { now.timeIntervalSince($0.value) < 60 }
        }
        lock.unlock()

        // critical 与 standard 都给「允许本次」；永久信任只对 standard 开放
        let tier = SecurityPolicy.tier(of: ev.module)
        let canTrust = (tier == .standard)

        // 走网关的能力都被挂起了，放行后能自动重放；
        // 直通模块（auth/app/permission）没有挂起，仍需用户回小程序再点一次
        let autoResume = (tier != nil)

        SecurityBanner.shared.show(
            module: ev.module,
            appName: ev.appName,
            reason: ev.reason,
            autoResume: autoResume,
            onAllowOnce: {
                OneShotGrant.shared.grant(module: ev.grantKey, appId: ev.appId)
                PendingCapabilityStore.shared.resume(appId: ev.appId, module: ev.module)
            },
            onTrust: canTrust ? {
                if let id = ev.appId {
                    TrustedCapabilities.shared.trust(appId: id, module: ev.module)
                }
                PendingCapabilityStore.shared.resume(appId: ev.appId, module: ev.module)
            } : nil
        )
    }
}
