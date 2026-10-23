import Foundation

/// 网关错误码。小程序侧通过 err.code 判断，宿主日志同时记录。
enum GatewayError: Error, CustomStringConvertible {
    case capabilityNotDeclared(String)
    case unsupported(String)
    case regionUnsupported(String)
    case userDenied(String)
    case methodNotFound(module: String, method: String)
    case invalidParams(String)
    case permissionDenied(String)
    case providerError(String)

    var code: String {
        switch self {
        case .capabilityNotDeclared: return "capability_not_declared"
        case .unsupported:           return "unsupported"
        case .regionUnsupported:     return "region_unsupported"
        case .userDenied:            return "user_denied"
        case .methodNotFound:        return "method_not_found"
        case .invalidParams:         return "invalid_params"
        case .permissionDenied:      return "permission_denied"
        case .providerError:         return "provider_error"
        }
    }

    var description: String {
        switch self {
        case .capabilityNotDeclared(let c): return "Capability not declared: \(c)"
        case .unsupported(let c):          return "Capability unsupported: \(c)"
        case .regionUnsupported(let c):    return "Capability unavailable in region: \(c)"
        case .userDenied(let c):           return "User denied: \(c)"
        case .methodNotFound(let m, let mm): return "Method not found: \(m).\(mm)"
        case .invalidParams(let s):        return "Invalid params: \(s)"
        case .permissionDenied(let c):     return "Permission denied: \(c)"
        case .providerError(let s):        return "Provider error: \(s)"
        }
    }

    /// 转成回传给逻辑层的 JSON
    var asJSON: [String: Any] {
        ["code": code, "message": description]
    }
}
