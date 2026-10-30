import Foundation

/// 模拟器环境下的可用性状态。
enum SimulatorAvailability: String, Codable {
    case available      // 模拟器可用
    case degraded       // 可用但有差异（如定位返回固定坐标）
    case unsupported    // 模拟器不支持，真机可用

    var displayName: String {
        switch self {
        case .available:   return "可用"
        case .degraded:    return "受限"
        case .unsupported: return "模拟器不可用"
        }
    }
}

/// 单项能力的元数据。
struct PermissionInfo: Identifiable {
    let id: String
    let displayName: String
    let detail: String
    let level: CapabilityLevel
    let simulator: SimulatorAvailability
    let simulatorNote: String?
}

/// 权限目录：所有已知能力的静态描述。
/// 模拟器不支持的能力**不隐藏**，而是标注状态，让用户知道真机上可用。
enum PermissionCatalog {
    static let all: [PermissionInfo] = [
        // 媒体
        .init(id: "camera", displayName: "相机", detail: "拍摄照片", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器无摄像头"),
        .init(id: "photo", displayName: "相册", detail: "选择图片（PHPicker 无需授权）", level: .l1,
              simulator: .available, simulatorNote: nil),
        .init(id: "microphone", displayName: "麦克风", detail: "录制音频", level: .l1,
              simulator: .degraded, simulatorNote: "模拟器使用 Mac 麦克风"),
        .init(id: "speech", displayName: "语音识别", detail: "语音转文字", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器无音频输入设备"),
        .init(id: "location", displayName: "定位", detail: "获取当前位置", level: .l1,
              simulator: .degraded, simulatorNote: "返回固定模拟坐标"),

        // 设备
        .init(id: "deviceInfo", displayName: "设备信息", detail: "型号、系统版本、屏幕尺寸", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "battery", displayName: "电池", detail: "电量与充电状态", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "network", displayName: "网络", detail: "网络类型与计费状态", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "motion", displayName: "陀螺仪", detail: "设备姿态角", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器无运动传感器"),
        .init(id: "bluetooth", displayName: "蓝牙", detail: "蓝牙状态与扫描", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器无蓝牙硬件"),
        .init(id: "biometric", displayName: "Face ID", detail: "生物识别验证", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器组件不稳定，已跳过"),

        // 系统集成
        .init(id: "contacts", displayName: "通讯录", detail: "读取联系人", level: .l1,
              simulator: .available, simulatorNote: nil),
        .init(id: "calendar", displayName: "日历", detail: "读取与写入日程", level: .l1,
              simulator: .available, simulatorNote: nil),
        .init(id: "reminder", displayName: "提醒事项", detail: "创建提醒", level: .l1,
              simulator: .available, simulatorNote: nil),
        .init(id: "notification", displayName: "通知", detail: "本地通知授权与推送", level: .l1,
              simulator: .available, simulatorNote: nil),
        .init(id: "share", displayName: "分享", detail: "系统分享面板", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "openURL", displayName: "打开链接/App", detail: "唤起浏览器、原生 App（URL Scheme）与系统界面", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "clipboard", displayName: "剪贴板", detail: "读写剪贴板", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "vibrate", displayName: "震动", detail: "触感反馈", level: .l0,
              simulator: .degraded, simulatorNote: "模拟器无触感马达"),

        // 数据
        .init(id: "storage", displayName: "本地存储", detail: "键值对存储", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "files", displayName: "文件", detail: "沙盒文件读写", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "http", displayName: "网络请求", detail: "HTTP 请求", level: .l0,
              simulator: .available, simulatorNote: nil),

        // 特殊
        .init(id: "health", displayName: "健康数据", detail: "步数等健康指标", level: .l2,
              simulator: .unsupported, simulatorNote: "需要真机签名与健康数据"),

        // 扩展
        .init(id: "savePhoto", displayName: "保存到相册", detail: "把图片写入系统相册", level: .l1,
              simulator: .available, simulatorNote: nil),
        .init(id: "tts", displayName: "文字转语音", detail: "离线朗读文本", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "qrScan", displayName: "二维码扫描", detail: "相机实时识别条码/二维码", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器无摄像头"),
        .init(id: "qrGenerate", displayName: "二维码生成", detail: "把文本画成二维码", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "ocr", displayName: "文字识别", detail: "图片转文字（Vision）", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "audio", displayName: "音频播放", detail: "播放本地音频", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "music", displayName: "音乐播放", detail: "播放本地/网络音乐，支持循环、音量与后台播放", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "metal", displayName: "GPU 算力", detail: "Metal 多核并行：滤镜/卷积/批量缩放/归约/矩阵乘/分形渲染", level: .l0,
              simulator: .available, simulatorNote: nil),
        // 独家能力
        .init(id: "sharedbus", displayName: "跨窗口联动", detail: "多开实例实时互通：广播事件/共享键值/订阅变更（LiveSync 独家）", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "ai", displayName: "AI 助手", detail: "小程序内唤起 AI：问答 + 可执行 wx 代码片段（wx.askAI 独家）", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "locationWatch", displayName: "持续定位", detail: "订阅位置更新", level: .l1,
              simulator: .degraded, simulatorNote: "返回固定模拟坐标"),
        .init(id: "bluetoothScan", displayName: "蓝牙扫描", detail: "扫描附近蓝牙设备", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器无蓝牙硬件"),
        .init(id: "communication", displayName: "拨号/短信/邮件", detail: "唤起系统通信界面", level: .l0,
              simulator: .degraded, simulatorNote: "模拟器无法实际拨出"),
        .init(id: "brightness", displayName: "屏幕亮度", detail: "读改系统亮度", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "screenAwake", displayName: "屏幕常亮", detail: "阻止自动息屏", level: .l0,
              simulator: .available, simulatorNote: nil),

        // 第三轮
        .init(id: "websocket", displayName: "WebSocket", detail: "长连接实时通信", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "image", displayName: "图片压缩", detail: "等比缩放与质量压缩", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "videoRecord", displayName: "视频录制", detail: "相机录制视频", level: .l1,
              simulator: .unsupported, simulatorNote: "模拟器无摄像头"),
        .init(id: "upload", displayName: "文件上传", detail: "multipart/form-data 上传", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "networkWatch", displayName: "网络监听", detail: "订阅网络状态变化", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "clipboardImage", displayName: "剪贴板图片", detail: "读写剪贴板图片", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "pdf", displayName: "PDF 生成", detail: "HTML 渲染为 PDF", level: .l0,
              simulator: .available, simulatorNote: nil),
        .init(id: "print", displayName: "打印", detail: "AirPrint 打印 PDF/图片", level: .l0,
              simulator: .degraded, simulatorNote: "模拟器无打印服务"),

        .init(id: "account", displayName: "账号信息", detail: "读取当前登录用户的公开信息", level: .l0,
              simulator: .available, simulatorNote: nil),

        .init(id: "spotlight", displayName: "系统搜索", detail: "把内容索引到 Spotlight，可在系统搜索中找到", level: .l0,
              simulator: .degraded, simulatorNote: "模拟器搜索行为受限"),
        .init(id: "liveActivity", displayName: "实时活动", detail: "锁屏/灵动岛展示进度与状态", level: .l2,
              simulator: .unsupported, simulatorNote: "需真机 iOS 16.1+ 且需 Widget Extension"),
    ]

    static let byID: [String: PermissionInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func info(_ id: String) -> PermissionInfo? { byID[id] }

    /// 供安装校验：manifest 中声明的能力是否都已知
    static func isKnown(_ id: String) -> Bool { byID[id] != nil }
}
