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
import AppTrackingTransparency
import MediaPlayer
import HomeKit
import CoreNFC
import Network
import NearbyInteraction

/// iOS 原生权限深度集成。
/// 统一查询与申请系统权限，返回细分状态：
/// authorized / denied / notDetermined / restricted / limited / unsupported
enum PermissionManager {

    /// 全部受支持的权限 ID
    static let supportedIDs: Set<String> = [
        "camera", "microphone", "location", "photo", "savePhoto",
        "contacts", "calendar", "reminder", "notification",
        "bluetooth", "motion", "speech", "biometric", "health",
        "att", "localNetwork", "nfc", "mediaLibrary", "homeKit", "nearby"
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

        // iOS 14+ App 追踪透明度（跨 App 追踪授权）
        case "att":
            if #available(iOS 14, *) {
                switch ATTrackingManager.trackingAuthorizationStatus {
                case .authorized:   complete("authorized", completion)
                case .denied:       complete("denied", completion)
                case .restricted:   complete("restricted", completion)
                default:            complete("notDetermined", completion)
                }
            } else {
                complete("unsupported", completion)
            }

        // 本地网络：iOS 无状态查询 API，未触发时恒为 notDetermined（首次访问才弹窗）
        case "localNetwork":
            if #available(iOS 14, *) {
                complete("notDetermined", completion)
            } else {
                complete("unsupported", completion)
            }

        // NFC：无授权状态，只有设备支持性；授权发生在每次扫描会话时
        case "nfc":
            if NFCTagReaderSession.readingAvailable {
                complete("notDetermined", completion)
            } else {
                complete("unsupported", completion)
            }

        // 媒体资料库 / Apple Music
        case "mediaLibrary":
            switch MPMediaLibrary.authorizationStatus() {
            case .authorized: complete("authorized", completion)
            case .denied:     complete("denied", completion)
            case .restricted: complete("restricted", completion)
            default:          complete("notDetermined", completion)
            }

        // HomeKit 智能家居（OptionSet 仅含 authorized/restricted，空集合 = 未决定或已拒绝）
        case "homeKit":
            let s = HMHomeManager().authorizationStatus
            if s.contains(.authorized) {
                complete("authorized", completion)
            } else if s.contains(.restricted) {
                complete("restricted", completion)
            } else {
                complete("notDetermined", completion)
            }

        // 近距离交互（U1 芯片）：无授权状态，只有设备支持性；首次会话时弹一次性允许
        case "nearby":
            if #available(iOS 14, *) {
                if NISession.isSupported {
                    complete("notDetermined", completion)
                } else {
                    complete("unsupported", completion)
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

        case "att":
            guard #available(iOS 14, *) else {
                complete("unsupported", completion)
                return
            }
            ATTrackingManager.requestTrackingAuthorization { _ in
                status(for: permission, completion: completion)
            }

        case "localNetwork":
            requestLocalNetwork(completion)

        case "nfc", "nearby":
            // 无程序化授权入口：授权发生在对应系统会话（NFC 扫描 / 近距离测量）启动时，
            // 此处仅回读设备支持状态，避免在非交互场景伪造弹窗。
            status(for: permission, completion: completion)

        case "mediaLibrary":
            MPMediaLibrary.requestAuthorization { _ in
                status(for: permission, completion: completion)
            }

        case "homeKit":
            requestHomeKit(completion)

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

    // MARK: - 本地网络 / HomeKit 申请辅助

    private static var localNetworkProbe: LocalNetworkProbe?

    /// 本地网络无状态 API，只能通过真实发起本地访问触发系统弹窗。
    /// 用一次短暂的 Bonjour 探测触发弹窗（约 4 秒后结束探测）。
    private static func requestLocalNetwork(_ completion: @escaping (String) -> Void) {
        guard #available(iOS 14, *) else {
            completion("unsupported")
            return
        }
        let probe = LocalNetworkProbe { status in
            localNetworkProbe = nil
            completion(status)
        }
        localNetworkProbe = probe
        probe.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            localNetworkProbe?.finish()
            localNetworkProbe = nil
            completion("notDetermined")
        }
    }

    private static var homeKitRequester: HMHomeManager?
    private static var homeKitDelegate: HomeKitRequestDelegate?

    /// HomeKit 在首次访问 homes 时弹授权窗，监听 didUpdateAuthorizationStatus 后回读状态
    private static func requestHomeKit(_ completion: @escaping (String) -> Void) {
        let mgr = HMHomeManager()
        homeKitRequester = mgr
        homeKitDelegate = HomeKitRequestDelegate {
            status(for: "homeKit") { s in
                completion(s)
                homeKitRequester = nil
                homeKitDelegate = nil
            }
        }
        mgr.delegate = homeKitDelegate
        _ = mgr.homes // 触发首次授权弹窗
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak mgr] in
            guard homeKitRequester === mgr else { return }
            status(for: "homeKit") { s in
                completion(s)
                homeKitRequester = nil
                homeKitDelegate = nil
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

/// 本地网络权限探测：发起一次 Bonjour 浏览触发 iOS 本地网络授权弹窗。
/// 无状态查询 API，探测结束后统一回 notDetermined（被拒的连接会报 NoAuth）。
private final class LocalNetworkProbe: NSObject, NetServiceBrowserDelegate {
    private let onFinish: (String) -> Void
    private var browser: NetServiceBrowser?
    private var finished = false

    init(_ onFinish: @escaping (String) -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    func start() {
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_kinter-probe._tcp", inDomain: "local.")
        browser = b
    }

    func finish() {
        guard !finished else { return }
        finished = true
        browser?.stop()
        browser = nil
        onFinish("notDetermined")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        finish()
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        // 已触发系统本地网络授权弹窗
    }
}

private final class HomeKitRequestDelegate: NSObject, HMHomeManagerDelegate {
    private let onChange: () -> Void
    init(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
    }
    func homeManagerDidUpdateAuthorizationStatus(_ manager: HMHomeManager) {
        onChange()
    }
}
