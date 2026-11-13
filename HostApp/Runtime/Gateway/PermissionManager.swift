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

    /// 共享定位管理器（authorizationStatus 实例属性需要持有实例）
    private static let locationManager = CLLocationManager()

    /// 查询单个权限状态（异步回调到主线程）
    static func status(for permission: String, completion: @escaping (String) -> Void) {
        switch permission {
        case "camera":
            let s = AVCaptureDevice.authorizationStatus(for: .video)
            complete(s.mapAVStatus, completion)

        case "microphone":
            if #available(iOS 17.0, *) {
                switch AVAudioApplication.shared.recordPermission {
                case .granted:    complete("authorized", completion)
                case .denied:     complete("denied", completion)
                default:          complete("notDetermined", completion)
                }
            } else {
                switch AVAudioSession.sharedInstance().recordPermission {
                case .granted:    complete("authorized", completion)
                case .denied:     complete("denied", completion)
                default:          complete("notDetermined", completion)
                }
            }

        case "location":
            let s = Self.locationManager.authorizationStatus
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

    /// 申请单个权限，回调最终状态。同一权限并发调用只弹一次系统弹窗，回调统一回传。
    static func request(_ permission: String, completion: @escaping (String) -> Void) {
        guard supportedIDs.contains(permission) else {
            complete("unsupported", completion)
            return
        }
        // 已有在飞请求：排队等待同一结果，不重复触发系统弹窗。
        guard enqueueInflight(permission, completion) else { return }

        func finishWithStatus() {
            status(for: permission) { s in flushInflight(permission, s) }
        }

        switch permission {
        case "camera":
            AVCaptureDevice.requestAccess(for: .video) { _ in finishWithStatus() }

        case "microphone":
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { _ in finishWithStatus() }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { _ in finishWithStatus() }
            }

        case "location":
            requestLocation(permission)

        case "photo":
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in finishWithStatus() }

        case "savePhoto":
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in finishWithStatus() }

        case "contacts":
            CNContactStore().requestAccess(for: .contacts) { _, _ in finishWithStatus() }

        case "calendar":
            if #available(iOS 17.0, *) {
                EKEventStore().requestFullAccessToEvents { _, _ in finishWithStatus() }
            } else {
                EKEventStore().requestAccess(to: .event) { _, _ in finishWithStatus() }
            }

        case "reminder":
            if #available(iOS 17.0, *) {
                EKEventStore().requestFullAccessToReminders { _, _ in finishWithStatus() }
            } else {
                EKEventStore().requestAccess(to: .reminder) { _, _ in finishWithStatus() }
            }

        case "notification":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                finishWithStatus()
            }

        case "bluetooth":
            requestBluetooth(permission)

        case "motion":
            // 首次 query 触发系统弹窗；直接返回当前状态
            finishWithStatus()

        case "speech":
            SFSpeechRecognizer.requestAuthorization { _ in finishWithStatus() }

        case "biometric":
            requestBiometric(permission)

        case "health":
            requestHealth(permission)

        case "att":
            guard #available(iOS 14, *) else {
                flushInflight(permission, "unsupported")
                return
            }
            ATTrackingManager.requestTrackingAuthorization { _ in finishWithStatus() }

        case "localNetwork":
            requestLocalNetwork(permission)

        case "nfc", "nearby":
            // 无程序化授权入口：授权发生在对应系统会话（NFC 扫描 / 近距离测量）启动时，
            // 此处仅回读设备支持状态，避免在非交互场景伪造弹窗。
            finishWithStatus()

        case "mediaLibrary":
            MPMediaLibrary.requestAuthorization { _ in finishWithStatus() }

        case "homeKit":
            requestHomeKit(permission)

        default:
            finishWithStatus()
        }
    }

    // MARK: - 异步申请辅助（需要强引用管理器直到回调）

    private static var locationRequester: CLLocationManager?
    private static var locationRequestDelegate: LocationRequestDelegate?
    fileprivate static var bluetoothRequester: CBCentralManager?
    fileprivate static var bluetoothPermission: String?
    /// 强持有蓝牙权限申请的 delegate（delegate 是 weak，必须有人持有否则立即释放）
    fileprivate static var bluetoothDelegate: BluetoothRequestDelegate?

    // MARK: - 并发去重

    /// 同一权限正在申请时，后续请求把回调排进队列；系统弹窗只弹一次，
    /// 最终状态到达后统一回传，避免第二个请求覆盖第一个导致回调丢失。
    private static let inflightLock = NSLock()
    private static var inflight: [String: [(String) -> Void]] = [:]

    /// 返回 true 表示本次是首发请求（需要触发系统弹窗）；false 表示已有在飞请求，仅排队。
    fileprivate static func enqueueInflight(_ permission: String,
                                        _ completion: @escaping (String) -> Void) -> Bool {
        inflightLock.lock()
        if inflight[permission] != nil {
            inflight[permission]?.append(completion)
            inflightLock.unlock()
            return false
        }
        inflight[permission] = [completion]
        inflightLock.unlock()
        return true
    }

    /// 在飞请求结束：取出全部排队回调，主线程统一回传后清空登记表。
    fileprivate static func flushInflight(_ permission: String, _ status: String) {
        inflightLock.lock()
        let queued = inflight[permission] ?? []
        inflight[permission] = nil
        inflightLock.unlock()
        DispatchQueue.main.async {
            queued.forEach { $0(status) }
        }
    }

    private static func requestLocation(_ permission: String) {
        let mgr = CLLocationManager()
        locationRequester = mgr
        let delegate = LocationRequestDelegate { _ in
            // 用户做出选择后查询状态
            status(for: permission) { s in
                locationRequester = nil
                locationRequestDelegate = nil
                flushInflight(permission, s)
            }
        }
        locationRequestDelegate = delegate
        mgr.delegate = delegate
        mgr.requestWhenInUseAuthorization()
        // 兜底：delegate 未在 3 秒内回调（如已是授权态）时也返回状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak mgr] in
            guard locationRequester === mgr else { return }
            status(for: permission) { s in
                locationRequester = nil
                locationRequestDelegate = nil
                flushInflight(permission, s)
            }
        }
    }

    private static func requestBluetooth(_ permission: String) {
        guard #available(iOS 13.1, *) else {
            flushInflight(permission, "unsupported")
            return
        }
        let mgr = CBCentralManager()
        bluetoothRequester = mgr
        bluetoothPermission = permission
        let delegate = BluetoothRequestDelegate()
        Self.bluetoothDelegate = delegate
        mgr.delegate = delegate
    }

    private static func requestBiometric(_ permission: String) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            status(for: permission) { s in flushInflight(permission, s) }
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "验证身份以授权小程序操作") { _, _ in
            status(for: permission) { s in flushInflight(permission, s) }
        }
    }

    private static func requestHealth(_ permission: String) {
        guard HKHealthStore.isHealthDataAvailable(),
              let read = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            flushInflight(permission, "unsupported")
            return
        }
        let store = HKHealthStore()
        // HealthKit 要 com.apple.developer.healthkit entitlement，自签名包没有时
        // requestAuthorization 会同步抛 ObjC 异常，不接住就是主线程 abort。
        // 真机崩溃日志（bug_type 309 / EXC_CRASH·SIGABRT）就是走到这里挂的。
        let thrown = ObjCExceptionCatcher.catchException {
            store.requestAuthorization(toShare: [], read: [read]) { _, _ in
                status(for: permission) { s in flushInflight(permission, s) }
            }
        }
        if thrown != nil {
            flushInflight(permission, "unsupported")
        }
    }

    // MARK: - 本地网络 / HomeKit 申请辅助

    private static var localNetworkProbe: LocalNetworkProbe?

    /// 本地网络无状态 API，只能通过真实发起本地访问触发系统弹窗。
    /// 用一次短暂的 Bonjour 探测触发弹窗（约 4 秒后结束探测）。
    private static func requestLocalNetwork(_ permission: String) {
        guard #available(iOS 14, *) else {
            flushInflight(permission, "unsupported")
            return
        }
        let probe = LocalNetworkProbe { status in
            localNetworkProbe = nil
            flushInflight(permission, status)
        }
        localNetworkProbe = probe
        probe.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            localNetworkProbe?.finish()
            localNetworkProbe = nil
            flushInflight(permission, "notDetermined")
        }
    }

    private static var homeKitRequester: HMHomeManager?
    private static var homeKitDelegate: HomeKitRequestDelegate?

    /// HomeKit 在首次访问 homes 时弹授权窗，监听 didUpdateAuthorizationStatus 后回读状态
    private static func requestHomeKit(_ permission: String) {
        let mgr = HMHomeManager()
        homeKitRequester = mgr
        homeKitDelegate = HomeKitRequestDelegate {
            status(for: permission) { s in
                homeKitRequester = nil
                homeKitDelegate = nil
                flushInflight(permission, s)
            }
        }
        mgr.delegate = homeKitDelegate
        _ = mgr.homes // 触发首次授权弹窗
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak mgr] in
            guard homeKitRequester === mgr else { return }
            status(for: permission) { s in
                homeKitRequester = nil
                homeKitDelegate = nil
                flushInflight(permission, s)
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
            switch CBManager.authorization {
            case .allowedAlways: status = "authorized"
            case .denied:        status = "denied"
            case .restricted:    status = "restricted"
            default:             status = "notDetermined"
            }
        } else {
            status = "unsupported"
        }
        if let permission = PermissionManager.bluetoothPermission {
            PermissionManager.flushInflight(permission, status)
        }
        PermissionManager.bluetoothPermission = nil
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
