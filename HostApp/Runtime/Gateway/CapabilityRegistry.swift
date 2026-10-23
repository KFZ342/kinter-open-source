import Foundation

final class CapabilityRegistry {
    static let shared = CapabilityRegistry()
    /// 能力 -> 级别
    private var levels: [String: CapabilityLevel] = [:]
    /// 能力 -> 工厂。每个 Gateway 会话通过工厂获得独立实例，避免状态串扰。
    private var factories: [String: () -> CapabilityProvider] = [:]
    private let lock = NSLock()
    private init() {}

    func register<P: CapabilityProvider>(_ type: P.Type) {
        lock.lock(); defer { lock.unlock() }
        levels[type.capability] = type.level
        factories[type.capability] = { type.init() }
    }

    func level(for c: String) -> CapabilityLevel? {
        lock.lock(); defer { lock.unlock() }
        return levels[c]
    }

    func allCapabilities() -> [String: CapabilityLevel] {
        lock.lock(); defer { lock.unlock() }
        return levels
    }

    /// 为指定 Gateway 创建一套独立实例。
    /// 锁内只拷贝工厂快照，实例构建在锁外进行，避免长锁阻塞注册。
    func makeFreshProviders() -> [String: CapabilityProvider] {
        let snapshot: [(String, () -> CapabilityProvider)]
        lock.lock(); defer { lock.unlock() }
        snapshot = factories.map { ($0.key, $0.value) }
        var out: [String: CapabilityProvider] = [:]
        for (cap, factory) in snapshot {
            out[cap] = factory()
        }
        return out
    }

    func registerBuiltins() {
        register(CameraProvider.self)
        register(PhotoProvider.self)
        register(LocationProvider.self)
        register(MicrophoneProvider.self)
        register(ClipboardProvider.self)
        register(StorageProvider.self)
        register(DeviceInfoProvider.self)
        register(BatteryProvider.self)
        register(NetworkProvider.self)
        register(VibrateProvider.self)
        register(OpenURLProvider.self)
        register(ShareProvider.self)
        register(ContactsProvider.self)
        register(CalendarProvider.self)
        register(ReminderProvider.self)
        register(NotificationProvider.self)
        register(SpeechProvider.self)
        register(HealthProvider.self)
        register(BluetoothProvider.self)
        register(MotionProvider.self)
        register(BiometricProvider.self)
        register(FilesProvider.self)
        register(HTTPProvider.self)
        // 扩展能力
        register(SavePhotoProvider.self)
        register(TTSProvider.self)
        register(QRScanProvider.self)
        register(QRGenerateProvider.self)
        register(OCRProvider.self)
        register(AudioPlayerProvider.self)
        register(MusicProvider.self)
        register(LocationWatchProvider.self)
        register(BluetoothScanProvider.self)
        register(CommunicationProvider.self)
        register(BrightnessProvider.self)
        register(ScreenAwakeProvider.self)
        // 第三轮：实时 / 媒体 / 系统
        register(WebSocketProvider.self)
        register(ImageProvider.self)
        register(VideoRecordProvider.self)
        register(UploadProvider.self)
        register(NetworkWatchProvider.self)
        register(ClipboardImageProvider.self)
        register(PDFProvider.self)
        register(PrintProvider.self)
        register(AccountProvider.self)
        register(SpotlightProvider.self)
        register(LiveActivityProvider.self)
    }
}
