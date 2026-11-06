import Foundation

/// 会话种子：安全模式每次开启生成一次，作为本会话所有记录的归属标识。
enum SessionSeed {
    private(set) static var sessionId: String = UUID().uuidString
    private(set) static var startedAt: Date = Date()

    static func startNewSession() {
        sessionId = UUID().uuidString
        startedAt = Date()
    }
}
