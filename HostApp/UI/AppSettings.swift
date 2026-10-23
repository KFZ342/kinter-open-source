import Foundation

/// 启动方式。
enum LaunchMode: String, Codable, CaseIterable {
    case normal       // 正常启动到导入页
    case library      // 启动直接进应用库
    case lastApp      // 启动直接进上次打开的应用
    case custom       // 启动直接进指定应用，带自定义参数

    var displayName: String {
        switch self {
        case .normal:  return "标准启动（进入首页）"
        case .library: return "直接进入应用库"
        case .lastApp: return "直接打开上次的应用"
        case .custom:  return "直接打开指定应用"
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let launchMode     = "settings.launchMode"
        static let lastAppId      = "settings.lastAppId"
        static let customAppId    = "settings.customAppId"
        static let customParams   = "settings.customParams"
        static let confirmInstall = "settings.confirmInstall"
        static let showWarnings   = "settings.showWarnings"
    }

    private init() {}

    var launchMode: LaunchMode {
        get {
            guard let raw = defaults.string(forKey: Key.launchMode),
                  let m = LaunchMode(rawValue: raw) else { return .normal }
            return m
        }
        set { defaults.set(newValue.rawValue, forKey: Key.launchMode) }
    }

    var lastOpenedAppId: String? {
        get { defaults.string(forKey: Key.lastAppId) }
        set { defaults.set(newValue, forKey: Key.lastAppId) }
    }

    /// 定制启动时要打开的应用 appId
    var customAppId: String? {
        get { defaults.string(forKey: Key.customAppId) }
        set { defaults.set(newValue, forKey: Key.customAppId) }
    }

    /// 定制启动时传给应用的参数（JSON 字符串）
    var customParams: String? {
        get { defaults.string(forKey: Key.customParams) }
        set { defaults.set(newValue, forKey: Key.customParams) }
    }

    /// 解析 customParams 成字典
    var customParamsDict: [String: Any]? {
        guard let s = customParams, !s.isEmpty,
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    var confirmInstall: Bool {
        get { defaults.object(forKey: Key.confirmInstall) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.confirmInstall) }
    }

    var showWarnings: Bool {
        get { defaults.object(forKey: Key.showWarnings) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showWarnings) }
    }

    /// 是否允许小程序读取当前登录账号的公开信息
    var allowAppsAccessAccount: Bool {
        get { defaults.object(forKey: "settings.allowAppsAccessAccount") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.allowAppsAccessAccount") }
    }

    /// GitHub OAuth 中转服务器地址，如 https://auth.example.com
    var authServerURL: String? {
        get { defaults.string(forKey: "settings.authServerURL") }
        set { defaults.set(newValue, forKey: "settings.authServerURL") }
    }
}
