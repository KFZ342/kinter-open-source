import Foundation

/// 小程序内 AI 助手 Provider（ai，L0）——Kinter 独家。
///
/// 微信/支付宝的小程序无法"在页面里直接唤起一个能回答问题的 AI 助手"。
/// Kinter 宿主内任意小程序页面调用 `wx.askAI({question, context})`，
/// 宿主用用户配置的模型（设置 → 模型）回答，返回：
/// - `answer`：AI 的纯文本回答
/// - `code`：可选的可执行 wx 代码片段（用 ```wx 代码块标记），
///   宿主**不自动执行**，由小程序开发者自行决定如何使用，杜绝注入风险。
final class AskAIProvider: CapabilityProvider, AppContextInjectable {
    static var capability: String { "ai" }
    static var level: CapabilityLevel { .l0 }

    var appId: String?
    private let client = AIClient()
    /// 单飞：同一时间只允许一个 ask 在途，避免并发打爆模型额度
    private var inflight = false

    init() {}

    func invoke(method: String,
                params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "ask" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        guard AISettings.shared.isConfigured else {
            completion(.failure(.unsupported("请先在设置 → 模型 中配置模型接口")))
            return
        }
        guard let question = params["question"] as? String, !question.isEmpty else {
            completion(.failure(.invalidParams("question 不能为空")))
            return
        }
        guard !inflight else {
            completion(.failure(.providerError("上一次询问还在进行中，请稍候")))
            return
        }
        inflight = true

        let context = (params["context"] as? String) ?? ""
        let system = """
        你是 Kinter 宿主内小程序的内置 AI 助手（wx.askAI 唤起）。
        当前运行环境：iOS WKWebView，可用 wx API（wx.toast/showModal、wx.request、\
        wx.getStorage/setStorage、wx.navigateTo、wx.getLocation 等 125 项能力）。
        规则：
        1. 用简洁中文直接回答用户问题，不要长篇大论。
        2. 如果用户需要代码帮助，输出一段可直接运行的 wx 代码片段，用 ```wx 代码块包裹，\
        代码只允许调用 wx.* API，禁止 fetch/XHR/DOM 直操作。
        3. 不询问任何个人敏感信息，不引导外链。
        """
        var messages: [AIClient.Message] = [
            .init(role: "system", content: system)
        ]
        if !context.isEmpty {
            messages.append(.init(role: "user", content: "（当前小程序上下文）\(context)"))
        }
        messages.append(.init(role: "user", content: question))

        client.chat(messages: messages) { [weak self] result in
            guard let self = self else { return }
            self.inflight = false
            switch result {
            case .success(let text):
                let parsed = Self.splitAnswerAndCode(text)
                completion(.success(parsed))
            case .failure(let err):
                let msg = (err as? LocalizedError)?.errorDescription ?? err.localizedDescription
                completion(.failure(.providerError(msg)))
            }
        }
    }

    /// 从模型回复中拆出 `answer` 与可选 `code`：
    /// - ```wx ... ```（也兼容 ```js / ```javascript）代码块提取为 code
    /// - 去除代码块后的正文作为 answer
    static func splitAnswerAndCode(_ text: String) -> [String: Any] {
        let ns = text as NSString
        var code: String?
        var clean = text

        let pattern = "```(?:wx|js|javascript)?\\s*\\n?([\\s\\S]*?)```"
        let range = ns.range(of: pattern, options: .regularExpression)
        if range.location != NSNotFound {
            let block = ns.substring(with: range) as NSString
            // 去掉首行 ``` 标记：找第一个换行
            let innerStart = block.range(of: "\n")
            if innerStart.location != NSNotFound {
                var inner = block.substring(from: innerStart.location + 1)
                if inner.hasSuffix("```") { inner = String(inner.dropLast(3)) }
                code = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // 无换行的单行块
                code = block.replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            clean = ns.replacingCharacters(in: range, with: "")
        }

        let answer = clean
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? text : clean.trimmingCharacters(in: .whitespacesAndNewlines)

        return ["answer": answer, "code": code ?? NSNull()]
    }
}
