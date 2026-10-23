import Foundation

/// 能力级别。网关按级别决定是否需要系统授权、地区检查、entitlement 校验。
enum CapabilityLevel: String, Codable {
    case l0 = "L0"
    case l1 = "L1"
    case l2 = "L2"
    case l3 = "L3"

    var requiresSystemPermission: Bool { self == .l1 || self == .l2 }
    var requiresEntitlement: Bool { self == .l2 }
}

/// Provider 协议。每个能力域实现一套，注册到 Registry。
protocol CapabilityProvider: AnyObject {
    static var capability: String { get }
    static var level: CapabilityLevel { get }
    init()

    /// 网关已完成 manifest、地区、权限检查，Provider 只负责执行。
    func invoke(method: String,
                params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void)
}

/// Provider 若依赖地区可用性（如 Foundation Models），实现此协议。
protocol RegionSensitiveProvider {
    /// 返回当前地区是否可用。国行设备返回 false 的能力，网关直接拒绝。
    static func isAvailableInCurrentRegion() -> Bool
}

/// Provider 若需要知道当前调用方 appId（文件隔离、Spotlight 域、Live Activity 归属等），实现此协议。
/// 网关在每次 invoke 前注入，取代原先对具体类型的硬编码判断。
protocol AppContextInjectable: AnyObject {
    var appId: String? { get set }
}
