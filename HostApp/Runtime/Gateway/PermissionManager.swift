import Foundation
import AVFoundation
import CoreLocation
import Contacts
import EventKit
import UserNotifications
import CoreBluetooth
import CoreMotion
import Speech
import LocalAuthentication
import HealthKit
import Photos

/// iOS 原生权限深度集成。
/// 统一查询与申请系统权限，返回细分状态：
/// authorized / denied / notDetermined / restricted / limited / unsupported
enum PermissionManager {

    /// 全部受支持的权限 ID
    static let supportedIDs: Set<String> = [
        "camera", "microphone", "location", "photo", "savePhoto",
        "contacts", "calendar", "reminder", "notification",
        "bluetooth", "motion", "speech", "biometric", "health"
    ]

    // MARK: - 状态查询

    /// 查询单个权限状态（异步回调到主线程）
    static func status(for permission: String, completion: @escaping (String) -> Void) {
        switch permission {
        case "camera":
            let s = AVCaptureDevice.authorizationStatus(for: .video)
            complete(s.mapAVStatus, completion)

        case "microphone":
            let s = AVAudioSession.sharedInstance().recordPermission
            switch s {
            case .granted:        complete("authorized", completion)
            case .denied:         complete("denied", completion)
            default:              complete("notDetermined", completion)
            }

        case "location":
            let s = CLLocationManager.authorizationStatus()
            switch s {
            case .authorizedWhenInUse, .authorizedAlways:
                complete("authorized", completion)
            case .denied:           complete("denied", completion)
            case .restricted:       complete("restricted", completion)
            default:                complete("notDetermined", completion)
            }

        case "photo", "savePhoto":
            let access: PHAuthorizationStatus
            if permission == "savePhoto" {
                access = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            } else {
                access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            }
            switch access {
            case .authorized:      complete("authorized", completion)
            case .limited:         complete("limited", completion)
            case .denied:          complete("denied", completion)
            case .restricted:      complete("restricted", completion)
            default:               complete("notDetermined", completion)
            }

        case "contacts":
            let s = CNContactStore.authorizationStatus(for: .contacts)
            complete(s.mapAVStatus, completion)

        case "calendar":
            let s = EKEventStore.authorizationStatus(for: .event)
            complete(s.mapEKStatus, completion)

        case "reminder":
            let s = EKEventStore.authorizationStatus(for: .reminder)
            complete(s.mapEKStatus, completion)

        case "notification":
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    complete("authorized", completion)
                case .denied:        complete("denied", completion)
                case .notDetermined: complete("notDetermined", completion)
                default:             complete("restricted", completion)
                }
            }

        case "bluetooth":
            if #available(iOS 13.1, *) {
                let s = CBCentralManager.authorization
                switch s {
                case .allowedAlways: complete("authorized", completion)
                case .denied:        complete("denied", completion)
                case .restricted:    complete("restricted", completion)
                default:             complete("notDetermined", completion)
                }
            } else {
                complete("unsupported", completion)
            }

        case "motion":
            let s = CMMotionActivityManager.authorizationStatus()
            switch s {
            case .authorized:      complete("authorized", completion)
            case .denied:          complete("denied", completion)
            case .restricted:      complete("restricted", completion)
            default:               complete("notDetermined", completion)
            }

        case "speech":
            let s = SFSpeechRecognizer.authorizationStatus()
            complete(s.mapAVStatus, completion)

        case "biometric":
            let ctx = LAContext()
            var err: NSError?
            if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
                complete("authorized", completion)
            } else if let e = err as? LAError {
                switch e.code {
                case .biometryNotAvailable, .biometryNotEnrolled:
                    complete("unsupported", completion)
                default:
                    complete("denied", completion)
                }
            } else {
                complete("denied", completion)
            }

        case "health":
            if HKHealthStore.isHealthDataAvailable(),
               let type = HKQuantityType.quantityType(forIdentifier: .stepCount) {
                switch HKHealthStore().authorizationStatus(for: type) {
                case .sharingAuthorized: complete("authorized", completion)
                case .sharingDenied:     complete("denied", completion)
                default:                 complete("notDetermined", completion)
                }
            } else {
                complete("unsupported", completion)
            }

        default:
            complete("unsupported", completion)
        }
    }

    /// 查询所有权限状态（供 wx.getSetting）
    static func allStatuses(completion: @escaping ([String: String]) -> Void) {
        var result: [String: String] = [:]
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "perm.status")
        for pid in supportedIDs {
            group.enter()
            status(for: pid) { s in
                queue.async {
                    result[pid] = s
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            completion(result)
        }
    }

    // MARK: - 申请授权

    /// 申请单个权限，回调最终状态
    static func request(_ permission: String, completion: @escaping (String) -> Void) {
        switch permission {
        case "camera":
            AVCaptureDevice.requestAccess(for: .video) { _ in
                status(for: permission, completion: completion)
            }

        case "microphone":
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                status(for: permission, completion: completion)
            }

        case "location":
            requestLocation(completion)

        case "photo":
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                status(for: permission, completion: completion)
            }

        case "savePhoto":
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
                status(for: permission, completion: completion)
            }

        case "contacts":
            CNContactStore().requestAccess(for: .contacts) { _, _ in
                status(for: permission, completion: completion)
            }

        case "calendar":
            EKEventStore().requestAccess(to: .event) { _, _ in
                status(for: permission, completion: completion)
            }

        case "reminder":
            EKEventStore().requestAccess(to: .reminder) { _, _ in
                status(for: permission, completion: completion)
            }

        case "notification":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                status(for: permission, completion: completion)
            }

        case "bluetooth":
            requestBluetooth(completion)

        case "motion":
            // 首次 query 触发系统弹窗；直接返回当前状态
            status(for: permission, completion: completion)

        case "speech":
            SFSpeechRecognizer.requestAuthorization { _ in
                status(for: permission, completion: completion)
            }

        case "biometric":
            requestBiometric(completion)

        case "health":
            requestHealth(completion)

        default:
            status(for: permission, completion: completion)
        }
    }

    // MARK: - 异步申请辅助（需要强引用管理器直到回调）

    private static var locationRequester: CLLocationManager?
    private static var locationRequestDelegate: LocationRequestDelegate?
    fileprivate static var bluetoothRequester: CBCentralManager?
    fileprivate static var bluetoothHandler: ((String) -> Void)?

    private static func requestLocation(_ completion: @escaping (String) -> Void) {
        let mgr = CLLocationManager()
        locationRequester = mgr
        let delegate = LocationRequestDelegate { _ in
            // 用户做出选择后查询状态
            status(for: "location") { s in
                completion(s)
                locationRequester = nil
                locationRequestDelegate = nil
            }
        }
        locationRequestDelegate = delegate
        mgr.delegate = delegate
        mgr.requestWhenInUseAuthorization()
        // 兜底：delegate 未在 3 秒内回调（如已是授权态）时也返回状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak mgr] in
            guard locationRequester === mgr else { return }
            status(for: "location") { s in
                completion(s)
                locationRequester = nil
                locationRequestDelegate = nil
            }
        }
    }

    private static func requestBluetooth(_ completion: @escaping (String) -> Void) {
        guard #available(iOS 13.1, *) else {
            completion("unsupported")
            return
        }
        let mgr = CBCentralManager()
        bluetoothRequester = mgr
        bluetoothHandler = completion
        mgr.delegate = BluetoothRequestDelegate()
    }

    private static func requestBiometric(_ completion: @escaping (String) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            status(for: "biometric", completion: completion)
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "验证身份以授权小程序操作") { _, _ in
            DispatchQueue.main.async {
                status(for: "biometric", completion: completion)
            }
        }
    }

    private static func requestHealth(_ completion: @escaping (String) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let read = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            completion("unsupported")
            return
        }
        let store = HKHealthStore()
        store.requestAuthorization(toShare: [], read: [read]) { _, _ in
            DispatchQueue.main.async {
                status(for: "health", completion: completion)
            }
        }
    }

    // MARK: - 映射

    private static func complete(_ s: String, _ completion: @escaping (String) -> Void) {
        DispatchQueue.main.async { completion(s) }
    }
}

// MARK: - 状态映射扩展

private extension AVAuthorizationStatus {
    var mapAVStatus: String {
        switch self {
        case .authorized:   return "authorized"
        case .denied:       return "denied"
        case .restricted:   return "restricted"
        default:            return "notDetermined"
        }
    }
}

private extension CNAuthorizationStatus {
    var mapAVStatus: String {
        switch self {
        case .authorized:   return "authorized"
        case .denied:       return "denied"
        case .restricted:   return "restricted"
        default:            return "notDetermined"
        }
    }
}

private extension SFSpeechRecognizerAuthorizationStatus {
    var mapAVStatus: String {
        switch self {
        case .authorized:   return "authorized"
        case .denied:       return "denied"
        case .restricted:   return "restricted"
        default:            return "notDetermined"
        }
    }
}

private extension EKAuthorizationStatus {
    var mapEKStatus: String {
        switch self {
        case .authorized:        return "authorized"
        case .denied:            return "denied"
        case .restricted:        return "restricted"
        default:                 return "notDetermined"
        }
    }
}

// MARK: - Delegate 辅助

private final class LocationRequestDelegate: NSObject, CLLocationManagerDelegate {
    private let onChange: (CLAuthorizationStatus) -> Void
    init(_ onChange: @escaping (CLAuthorizationStatus) -> Void) {
        self.onChange = onChange
        super.init()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange(manager.authorizationStatus)
    }
}

private final class BluetoothRequestDelegate: NSObject, CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let status: String
        if #available(iOS 13.1, *) {
            switch central.authorization {
            case .allowedAlways: status = "authorized"
            case .denied:        status = "denied"
            case .restricted:    status = "restricted"
            default:             status = "notDetermined"
            }
        } else {
            status = "unsupported"
        }
        PermissionManager.bluetoothHandler?(status)
        PermissionManager.bluetoothHandler = nil
        PermissionManager.bluetoothRequester = nil
    }
}
