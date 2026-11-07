import Foundation

/// 敏感能力的三档策略。
/// 防误判的核心：不是所有敏感能力都该被无差别拒绝。
enum CapabilityTier {
    /// 高危：涉及隐私数据本身，安全模式下默认拒绝，只能「允许本次」。
    /// 通讯录、健康、麦克风、剪贴板——这些一旦泄露无法挽回。
    case critical
    /// 中危：需要用户上下文才合理，默认拒绝，可一次性放行、可加入信任清单。
    /// 相机、定位、相册——正常小程序大量使用，一律拒会误伤。
    case standard
    /// 外发通道：默认放行但记录；只有与高危能力「组合」出现时才告警。
    /// http/upload/websocket/ai——单独拒绝会让绝大多数 app 直接残废。
    case network
    /// 低敏：设备信息、震动、播放本地音频这类，拦了只会让用户烦。只记录，不拦。
    case benign

    var isAlwaysDenied: Bool { self == .critical }
    var canTrustPermanently: Bool { self == .standard }
    /// 是否计入「敏感」：benign 不算，隐私页的敏感统计与组合规则都不含它
    var isSensitive: Bool { self != .benign }
}

/// 能力分级表。集中在这里，SecurityMode/Interceptor 只查表，不硬编码。
enum SecurityPolicy {

    /// 能力 → 档位。50 项能力全部登记，不存在「野生能力」走默认放行。
    ///
    /// 新增能力时**必须**在这里登记：启动时会跑 auditCoverage()，
    /// 把没分级的能力打到控制台，避免"悄悄多出一条没人管的能力"。
    static let tiers: [String: CapabilityTier] = [
        // ===== 高危：隐私数据本体，默认拒绝，只给「允许本次」 =====
        "contacts": .critical,
        "health": .critical,
        "microphone": .critical,
        "speech": .critical,
        "videoRecord": .critical,
        "clipboard": .critical,
        "clipboardImage": .critical,
        // 生物识别（Face ID / Touch ID）等同于身份凭据，归高危
        "biometric": .critical,
        "motion": .critical,
        "calendar": .critical,
        "reminder": .critical,
        // 账号身份：读得到"谁在用这台设备"，和通讯录同级
        "account": .critical,

        // ===== 中危：可一次性放行 + 可信任 =====
        "camera": .standard,
        "photo": .standard,
        "savePhoto": .standard,
        "location": .standard,
        "bluetooth": .standard,
        "bluetoothScan": .standard,
        // 持续定位比单次定位更敏感，但它不是"隐私数据本体"，仍按 standard 处理
        "locationWatch": .standard,
        // 扫码/识字都是"用相机或相册看一眼"，与拍照同级
        "qrScan": .standard,
        "ocr": .standard,
        // 通知会把小程序内容推到桌面/锁屏，算一次对外露出
        "notification": .standard,
        // 实时活动写的是锁屏与灵动岛，内容离开 App 界面
        "liveActivity": .standard,

        // ===== 外发通道：默认放行，只记录 + 组合规则 =====
        "http": .network,
        "upload": .network,
        "websocket": .network,
        // ai 会把握手内容发给用户配置的第三方模型，是最容易被忽视的静默外发通道
        "ai": .network,
        // 下列通道由用户主动确认（弹系统面板/换到别的 App），不算静默外发，
        // 但仍登记为 network，纳入组合规则与记录，避免"读剪贴板后拼接 URL 跳转"漏检
        "openURL": .network,
        "share": .network,
        "communication": .network,
        // 可以拉远程音频流，也是外发通道
        "music": .network,
        // 打印把内容交给外部设备/服务
        "print": .network,

        // ===== 低敏：只记录，不拦 =====
        "files": .benign,          // 只能读写小程序自己的目录
        "storage": .benign,
        "deviceInfo": .benign,
        "battery": .benign,
        "network": .benign,
        "networkWatch": .benign,
        "vibrate": .benign,
        "brightness": .benign,
        "screenAwake": .benign,
        "tts": .benign,
        "qrGenerate": .benign,
        "image": .benign,
        "pdf": .benign,
        "audio": .benign,
        "metal": .benign,
        "sharedbus": .benign,
        "spotlight": .benign
    ]

    /// 恒定拒绝的能力：即使被误注册、被 AI 旁路调用，也不放行、不提供授权入口。
    /// badQuery 依赖 containermanager 私有符号做沙盒逃逸，永远不该出现在安全模式白名单里。
    static let hardDenied: Set<String> = ["badQuery"]

    /// 是否属于安全模式要拦的敏感能力（benign 不算）
    static func isSensitive(_ module: String) -> Bool {
        tiers[module]?.isSensitive ?? false
    }

    static func tier(of module: String) -> CapabilityTier? {
        tiers[module]
    }

    /// 是否恒定拒绝（无授权入口）
    static func isHardDenied(_ module: String) -> Bool {
        hardDenied.contains(module)
    }

    /// 组合规则的窗口：按"被读过的东西有多敏感"决定，而不是一刀切 5 秒。
    /// 通讯录/健康/剪贴板这类数据本体，读完一分钟内外发都算可疑；
    /// 相机/麦克风只证明"刚用过"，10 秒足够。
    static func comboWindow(for module: String) -> TimeInterval {
        switch module {
        case "contacts", "health", "clipboard", "clipboardImage",
             "calendar", "reminder", "speech", "biometric", "account":
            return 60
        case "camera", "photo", "microphone", "videoRecord",
             "motion", "location", "locationWatch", "qrScan", "ocr", "liveActivity":
            return 10
        default:
            return 0
        }
    }

    /// 启动自检：把注册表里有、但分级表里没登记的能力打出来。
    /// 不阻断启动，但 release 也打——这就是"新加能力必须被看见"的兜底。
    @discardableResult
    static func auditCoverage(against capabilities: [String: CapabilityLevel]) -> [String] {
        let missing = capabilities.keys
            .filter { tiers[$0] == nil && !hardDenied.contains($0) }
            .sorted()
        if !missing.isEmpty {
            NSLog("[SecurityPolicy] ⚠️ 未分级能力 %d 个：%@", missing.count, missing.joined(separator: ", "))
        }
        return missing
    }

    /// 中文名（横幅/报告用）
    static func displayName(for module: String) -> String {
        switch module {
        case "camera": return "相机"
        case "photo": return "相册"
        case "savePhoto": return "保存到相册"
        case "microphone": return "麦克风"
        case "videoRecord": return "录像"
        case "speech": return "语音识别"
        case "location": return "定位"
        case "contacts": return "通讯录"
        case "clipboard", "clipboardImage": return "剪贴板"
        case "http": return "网络请求"
        case "upload": return "上传"
        case "websocket": return "长连接"
        case "ai": return "内置 AI"
        case "openURL": return "打开外部链接"
        case "share": return "分享"
        case "communication": return "拨号/短信/邮件"
        case "health": return "健康数据"
        case "motion": return "运动数据"
        case "calendar": return "日历"
        case "reminder": return "提醒事项"
        case "bluetooth", "bluetoothScan": return "蓝牙"
        case "locationWatch": return "持续定位"
        case "biometric": return "生物识别"
        case "qrScan": return "扫码"
        case "ocr": return "文字识别"
        case "notification": return "通知"
        case "liveActivity": return "实时活动"
        case "account": return "账号信息"
        case "files": return "文件"
        case "storage": return "本地存储"
        case "deviceInfo": return "设备信息"
        case "battery": return "电量"
        case "network": return "网络状态"
        case "networkWatch": return "网络监听"
        case "vibrate": return "震动"
        case "brightness": return "屏幕亮度"
        case "screenAwake": return "屏幕常亮"
        case "tts": return "朗读"
        case "qrGenerate": return "生成二维码"
        case "image": return "图片处理"
        case "pdf": return "PDF"
        case "audio": return "音频播放"
        case "music": return "音乐播放"
        case "metal": return "GPU 渲染"
        case "sharedbus": return "跨窗口总线"
        case "spotlight": return "Spotlight 索引"
        case "print": return "打印"
        // 直通模块
        case "auth": return "账号信息"
        case "app": return "拉起其他应用"
        case "permission": return "系统权限弹窗"
        case "store": return "本地存储"
        case "popup", "router": return "界面路由"
        case "badQuery": return "沙盒越权"
        default: return module
        }
    }
}
