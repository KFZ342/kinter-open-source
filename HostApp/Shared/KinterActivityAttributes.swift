import ActivityKit
import Foundation

/// 实时活动的共享定义。主 App 与 Widget Extension 共用。
struct KinterActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String?
        var progress: Double?
        var status: String?
        /// 深链参数，点击活动时附加到 kinter://open?appId=xxx 后
        var deepLink: String?
    }

    var appId: String
    var appName: String
}
