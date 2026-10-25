import AVFoundation
import UIKit

/// 后台保活：循环播放一段无声音频，让宿主 App 进入后台后保持"正在播放音频"状态，
/// 被系统挂起/回收的优先级降低（延长存活时间）。
///
/// 注意（如实告知）：
/// - iOS 不保证后台永久存活，系统仍可能在内存压力下回收 App；
/// - App Store 审核对以保活为唯一目的的 audio 后台模式有拒绝风险，
///   因此本功能默认关闭，用户在设置中手动开启。
final class KeepAliveAudioPlayer {
    static let shared = KeepAliveAudioPlayer()

    private var player: AVAudioPlayer?
    private(set) var isRunning = false
    private let enabledKey = "keepalive.audio.enabled"

    /// 用户设置开关
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { start() } else { stop() }
        }
    }

    private init() {
        // App 进入后台/前台时自动启停（后台触发保活，回前台短暂暂停避免常驻占音频）
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// App 启动时调用：开关开着则延迟启动
    func autoApply() {
        guard isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // mixWithOthers：不抢占用户正在播放的其他音频（保持静音且不打断）
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav"),
                  let p = try? AVAudioPlayer(contentsOf: url) else {
                print("[KeepAlive] 静音音频资源不可用")
                return
            }
            p.numberOfLoops = -1      // 无限循环
            p.volume = 0.0            // 绝对静音
            p.prepareToPlay()
            p.play()
            player = p
            isRunning = true
            print("[KeepAlive] 无声音频保活已启动")
        } catch {
            print("[KeepAlive] 启动失败: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        player?.stop()
        player = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[KeepAlive] 无声音频保活已停止")
    }

    @objc private func appDidEnterBackground() {
        if isEnabled && !isRunning { start() }
    }

    @objc private func appWillEnterForeground() {
        // 回前台短暂停止，避免与前台音频播放冲突；必要时再次启动
        if isEnabled { stop() }
    }
}
