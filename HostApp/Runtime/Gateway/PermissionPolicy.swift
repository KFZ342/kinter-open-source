import AVFoundation
import CoreLocation

/// 权限策略。
/// L0：直接放行。
/// L1/L2：检查系统授权状态；notDetermined 放行，由 Provider 内部 requestAccess。
/// photo 使用 PHPicker，不需要相册权限，直接放行。
final class PermissionPolicy {
    static let shared = PermissionPolicy()

    /// 复用的定位管理器实例，仅用于查询授权状态
    private static let locationManager = CLLocationManager()

    private init() {}

    func check(module: String, level: CapabilityLevel, completion: @escaping (Bool) -> Void) {
        switch level {
        case .l0:
            completion(true)
        case .l3:
            completion(false)
        case .l1, .l2:
            checkSystemPermission(module: module, completion: completion)
        }
    }

    private func checkSystemPermission(module: String, completion: @escaping (Bool) -> Void) {
        switch module {
        case "camera":
            let s = AVCaptureDevice.authorizationStatus(for: .video)
            completion(s == .authorized || s == .notDetermined)
        case "microphone":
            let s = AVAudioSession.sharedInstance().recordPermission
            completion(s == .granted || s == .undetermined)
        case "location":
            // 复用单例，避免每次调用新建 CLLocationManager
            let status = Self.locationManager.authorizationStatus
            completion(status == .authorizedWhenInUse || status == .authorizedAlways || status == .notDetermined)
        default:
            // photo 走 PHPicker、storage/clipboard/deviceInfo 无需系统授权
            completion(true)
        }
    }
}
