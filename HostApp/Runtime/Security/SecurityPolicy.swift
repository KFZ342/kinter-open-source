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
    /// 低危：外发通道。默认放行但记录；只有与高危能力「组合」出现时才告警。
    /// http/upload/websocket/ai——单独拒绝会让绝大多数 app 直接残废。
    case network

    var isAlwaysDenied: Bool { self == .critical }
    var canTrustPermanently: Bool { self == .standard }
}

/// 能力分级表。集中在这里，SecurityMode/Interceptor 只查表，不硬编码。
enum SecurityPolicy {

    /// 能力 → 档位。未列出的模块视为非敏感（放行但全程记录）。
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

        // ===== 中危：可一次性放行 + 可信任 =====
        "camera": .standard,
        "photo": .standard,
        "savePhoto": .standard,
        "location": .standard,
        "bluetooth": .standard,
        "bluetoothScan": .standard,
        // 持续定位比单次定位更敏感，但它不是"隐私数据本体"，仍按 standard 处理
        "locationWatch": .standard,

        // ===== 低危：外发通道，默认放行，只记录 + 组合规则 =====
        "http": .network,
        "upload": .network,
        "websocket": .network,
        // ai 会把握手内容发给用户配置的第三方模型，是最容易被忽视的静默外发通道
        "ai": .network,
        // 下列通道由用户主动确认（弹系统面板/换到别的 App），不算静默外发，
        // 但仍登记为 network，纳入组合规则与记录，避免"读剪贴板后拼接 URL 跳转"漏检
        "openURL": .network,
        "share": .network,
        "communication": .network
    ]

    /// 恒定拒绝的能力：即使被误注册、被 AI 旁路调用，也不放行、不提供授权入口。
    /// badQuery 依赖 containermanager 私有符号做沙盒逃逸，永远不该出现在安全模式白名单里。
    static let hardDenied: Set<String> = ["badQuery"]

    /// 是否属于安全模式管辖的敏感能力
    static func isSensitive(_ module: String) -> Bool {
        tiers[module] != nil
    }

    static func tier(of module: String) -> CapabilityTier? {
        tiers[module]
    }

    /// 是否恒定拒绝（无授权入口）
    static func isHardDenied(_ module: String) -> Bool {
        hardDenied.contains(module)
    }

    /// 启动自检：把注册表里有、但分级表里没登记的能力打出来。
    /// 只影响 DEBUG，不阻断启动；目的是让"新加能力"这件事必须被看见。
    static func auditCoverage(against capabilities: [String: CapabilityLevel]) {
        #if DEBUG
        let missing = capabilities.keys
            .filter { tiers[$0] == nil && !hardDenied.contains($0) }
            .sorted()
        if !missing.isEmpty {
            print("[SecurityPolicy] ⚠️ 未分级能力 \(missing.count) 个：\(missing.joined(separator: ", "))")
        }
        #endif
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
