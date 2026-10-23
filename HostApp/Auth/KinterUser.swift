import Foundation

/// Kinter 账号用户信息。
struct KinterUser: Codable, Equatable {
    let id: String
    let username: String
    let name: String?
    let createdAt: String?

    var displayName: String { name ?? username }
}

/// 登录状态。
enum AuthState: Equatable {
    case loggedOut
    case loggedIn(KinterUser)

    var isLoggedIn: Bool {
        if case .loggedIn = self { return true }
        return false
    }

    var user: KinterUser? {
        if case .loggedIn(let u) = self { return u }
        return nil
    }
}
