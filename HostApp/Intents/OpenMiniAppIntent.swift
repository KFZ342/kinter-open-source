import AppIntents
import UIKit

/// 打开指定的小程序。
/// 用户可以对着 Siri 说「用 Kinter 打开计算器」，或在快捷指令里拖这个动作。
struct OpenMiniAppIntent: AppIntent {
    static var title: LocalizedStringResource = "打开小程序"
    static var description = IntentDescription("用 Kinter 打开一个已安装的小程序")

    /// 是否在前台打开 App
    static var openAppWhenRun: Bool = true

    @Parameter(title: "应用")
    var app: MiniAppEntity

    @Parameter(title: "初始参数", description: "传给小程序的 JSON 字符串，可选")
    var launchParams: String?

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$app
            \.$launchParams
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 解析可选参数
        var params: [String: Any]?
        if let json = launchParams, !json.isEmpty,
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            params = obj
        }

        // 通过 URL Scheme 唤起，保证无论 App 是否在运行都能正确处理
        var components = URLComponents()
        components.scheme = "kinter"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "appId", value: app.id)]
        if let p = params,
           let pd = try? JSONSerialization.data(withJSONObject: p),
           let ps = String(data: pd, encoding: .utf8) {
            components.queryItems?.append(URLQueryItem(name: "params", value: ps))
        }

        guard let url = components.url else {
            return .result(dialog: "参数无效")
        }

        let opened = await UIApplication.shared.open(url)
        if opened {
            return .result(dialog: "正在打开「\(app.name)」")
        } else {
            return .result(dialog: "无法打开「\(app.name)」")
        }
    }
}
