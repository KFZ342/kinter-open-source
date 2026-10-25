import Foundation
import UIKit

/// Kinter AI Agent：对话式小程序管理器。
/// 标准 Agent Loop（ReAct）：LLM 自主推理 → 决定调用工具 → 宿主执行 → 结果回灌 → 循环 → 直到输出最终回复。
final class AgentRuntime {

    // MARK: - 会话消息

    /// 工具执行结果卡片（点击可查看详细信息）
    struct AgentCard {
        let type: String      // generate / iterate / install / publish / list / delete / open / export / qr / stats / browse
        let title: String     // 卡片标题（如应用名）
        let subtitle: String  // 副标题（版本/价格等）
        let summary: String   // 卡片正文摘要（支持 Markdown）
        let detail: String    // 详情（点击展开，支持 Markdown）
    }

    struct ChatMessage {
        let role: String        // user / agent / tool
        var text: String
        var isStreaming: Bool   // 是否正在流式输出
        var card: AgentCard?    // 工具执行结果卡片（有值则 UI 渲染成卡片）
        var isToolCallFrame: Bool = false  // 是否工具调用帧（不注入 LLM 上下文）
    }

    /// 工具执行结果（结构化回灌给 LLM）
    struct ToolResult {
        let tool: String
        let input: String       // recordTool 用
        let summary: String     // 回灌给 LLM 的结果文本
        let card: AgentCard?    // UI 卡片
    }

    /// 工具执行记录（回灌给 AI：后续对话能感知执行过什么）
    struct ToolCallRecord {
        let tool: String
        let input: String
        let result: String
    }

    // MARK: - 状态

    private(set) var messages: [ChatMessage] = []
    private(set) var isBusy = false
    /// 本会话工具执行记录（回灌 AI 上下文）
    private(set) var toolHistory: [ToolCallRecord] = []

    /// UI 回调：需要弹出一个视图控制器（导出分享面板 / 二维码预览）
    var onPresent: ((UIViewController) -> Void)?

    /// 本轮生成的小程序（尚未安装/已安装都可操作）
    private(set) var generated: AIGenerator.GeneratedApp?
    private(set) var generatedDir: URL?
    /// 进入会话时绑定的已装小程序（迭代模式）
    private(set) var boundApp: InstalledApp?

    /// UI 回调：有新消息/状态变化
    var onUpdate: (() -> Void)?
    /// UI 回调：需要打开某个小程序（由宿主 UI 调 MiniAppLauncher）
    var onOpenApp: ((InstalledApp) -> Void)?
    /// 流式输出回调（追加文本，UI 刷新对应气泡）
    var onStream: ((String) -> Void)?

    private var currentClient: AIClient?
    private var lastPrompt = ""
    /// 忙时排队的待处理消息（处理完上一条自动接上，不再吞消息）
    private var pendingQueue: [String] = []
    /// Agent 循环最大轮数（防死循环）
    private let maxAgentRounds = 6

    init(boundApp: InstalledApp? = nil) {
        self.boundApp = boundApp
        var opener = "我是你的小程序 AI 管家（Agent 模式），可以自己规划工具调用帮你生成、修改、安装、发布、打开、删除、导出小程序，还能生成二维码、统计和逛商店。"
        if let app = boundApp {
            opener += "\n\n当前正在处理小程序「\(app.name)」（v\(app.version)），你可以直接说“把主题改成深色”“加一个计时功能”等。"
        }
        messages = [
            ChatMessage(role: "agent", text: opener, isStreaming: false)
        ]
    }

    // MARK: - 发送（进入 Agent Loop）

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: "user", text: trimmed, isStreaming: false))
        onUpdate?()
        if isBusy {
            pendingQueue.append(trimmed)
            appendAgent("⏳ 正在处理上一条，这条已排队，马上接上…")
            onUpdate?()
            return
        }
        lastPrompt = trimmed
        startAgent(round: 0)
    }

    // MARK: - Agent Loop 核心

    /// 第 round 轮：请求 LLM → 解析（工具调用 or 最终回复）
    private func startAgent(round: Int) {
        guard round < maxAgentRounds else {
            appendAgent("⚠️ 任务较复杂，已达到最大推理轮数。可以拆成几步来问我。")
            completeAction()
            return
        }
        isBusy = true
        let bubble = ChatMessage(role: "agent", text: "", isStreaming: true)
        messages.append(bubble)
        onUpdate?()

        let client = AIClient()
        currentClient = client
        client.chatStream(
            messages: agentLLMMessages(),
            onReasoning: { [weak self] _ in self?.onUpdate?() },
            onDelta: { [weak self] chunk in self?.streamAppend(bubbleIdx: nil, text: chunk) },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.closeStreamingBubble()
                switch result {
                case .success(let raw):
                    if let call = Self.parseToolCall(raw) {
                        // 工具调用：把流式气泡标记为工具调用帧，执行工具
                        if let idx = self.messages.lastIndex(where: { $0.role == "agent" && !$0.isToolCallFrame }) {
                            self.messages[idx].text = "🔧 正在执行工具「\(call.tool)」…"
                            self.messages[idx].isToolCallFrame = true
                        }
                        self.onUpdate?()
                        self.executeToolCall(call.tool, args: call.args, round: round)
                    } else {
                        // 最终回复（气泡已保留流式内容）
                        self.completeAction()
                    }
                case .failure(let err):
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.appendAgent("⚠️ 请求失败：\(err.localizedDescription)")
                        self.completeAction()
                    }
                }
            }
        )
    }

    /// 工具执行结果回灌 → 下一轮推理
    private func feedBack(_ result: ToolResult, round: Int) {
        recordTool(tool: result.tool, input: result.input, result: result.summary)
        messages.append(ChatMessage(role: "tool",
                                    text: "工具「\(result.tool)」执行结果：\(result.summary)",
                                    isStreaming: false,
                                    card: result.card))
        onUpdate?()
        startAgent(round: round + 1)
    }

    /// 构造发给 LLM 的消息（注入工具 schema + 会话历史 + 工具记录）
    private func agentLLMMessages() -> [AIClient.Message] {
        var msgs: [AIClient.Message] = []
        msgs.append(.init(role: "system",
                          content: AIPrompt.agentSystem(installed: installedListText(),
                                                        boundName: boundApp?.name)
                            + toolHistoryText()))
        for m in messages {
            if m.isStreaming || m.isToolCallFrame { continue }
            switch m.role {
            case "user":
                msgs.append(.init(role: "user", content: m.text))
            case "agent":
                if let card = m.card {
                    // 卡片消息：用摘要回灌（真实执行结果）
                    msgs.append(.init(role: "assistant", content: "（已执行工具，结果：）\(card.summary)"))
                } else if !m.text.isEmpty {
                    msgs.append(.init(role: "assistant", content: m.text))
                }
            case "tool":
                // 纯文本协议：工具结果以 user 角色回灌（部分 OpenAI 兼容服务要求
                // tool 消息必须携带 tool_call_id 配对，纯文本方案统一走 user 最稳）
                msgs.append(.init(role: "user", content: "【工具执行结果】\(m.text)"))
            default:
                break
            }
        }
        return msgs
    }

    /// 宽松解析 LLM 输出中的工具调用 JSON：{"tool":"xxx","args":{...}}
    static func parseToolCall(_ raw: String) -> (tool: String, args: [String: Any])? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = t.firstIndex(of: "{"),
              let close = t.lastIndex(of: "}"),
              open < close else { return nil }
        let jsonStr = String(t[open...close])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = obj["tool"] as? String else { return nil }
        var args: [String: Any] = [:]
        if let dict = obj["args"] as? [String: Any] {
            args = dict
        } else if let str = obj["args"] as? String {
            args["text"] = str
        } else if let prompt = obj["prompt"] as? String {
            args["prompt"] = prompt
        }
        return (tool, args)
    }

    // MARK: - 工具分发

    private func executeToolCall(_ tool: String, args: [String: Any], round: Int) {
        switch tool {
        case "generate":
            let prompt = (args["prompt"] as? String) ?? (args["text"] as? String) ?? lastPrompt
            runGenerateTool(prompt: prompt, round: round)
        case "iterate":
            let instruction = (args["instruction"] as? String) ?? (args["text"] as? String) ?? ""
            runIterateTool(instruction: instruction, round: round)
        case "install":
            feedBack(installToolResult(), round: round)
        case "publish":
            let price = (args["price"] as? NSNumber)?.doubleValue ?? 0
            runPublishTool(price: price, round: round)
        case "open":
            openToolResult(appId: resolveAppId(args))
            feedBack(ToolResult(tool: "open", input: "打开", summary: "已请求打开小程序", card: nil), round: round)
        case "list":
            feedBack(listToolResult(), round: round)
        case "delete":
            feedBack(deleteToolResult(appId: resolveAppId(args)), round: round)
        case "export":
            let appId = (args["appId"] as? String).flatMap { matchedInstalledAppID($0) }
            feedBack(exportToolResult(appId: appId), round: round)
        case "qr":
            let text = (args["text"] as? String) ?? (args["content"] as? String) ?? ""
            feedBack(qrToolResult(text: text), round: round)
        case "stats":
            feedBack(statsToolResult(), round: round)
        case "browse":
            browseToolResult(round: round)
        default:
            feedBack(ToolResult(tool: tool, input: tool,
                                summary: "未知工具「\(tool)」，请只从提供的工具中选择",
                                card: nil), round: round)
        }
    }

    /// 把 args 里的 appId/name 解析成应用 ID
    private func resolveAppId(_ args: [String: Any]) -> String? {
        if let id = args["appId"] as? String { return id }
        if let name = args["name"] as? String { return matchedInstalledAppID(name) }
        if let target = args["target"] as? String { return matchedInstalledAppID(target) }
        return nil
    }

    // MARK: - 异步工具（内部再调 LLM / 网络）

    /// generate：内部调 LLM 生成小程序代码包
    private func runGenerateTool(prompt: String, round: Int) {
        isBusy = true
        let client = AIClient()
        currentClient = client
        client.chatStream(
            messages: [
                .init(role: "system", content: AIPrompt.system),
                .init(role: "user", content: AIPrompt.user(prompt))
            ],
            onReasoning: { _ in },
            onDelta: { _ in },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let raw):
                    self.handleGenerated(raw: raw, prompt: prompt, round: round)
                case .failure(let err):
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.feedBack(ToolResult(tool: "generate", input: prompt,
                                                 summary: "生成失败：\(err.localizedDescription)",
                                                 card: nil), round: round)
                    }
                }
            }
        )
    }

    private func handleGenerated(raw: String, prompt: String, round: Int) {
        do {
            let app = try AIGenerator.parse(raw)
            AIGenerator.writeToDisk(app) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let dir):
                    self.generated = app
                    self.generatedDir = dir
                    let filesList = app.files.keys.sorted()
                        .map { "`\($0)` · \(String(app.files[$0]?.count ?? 0)) 字符" }
                        .joined(separator: "\n")
                    let caps = app.capabilities.isEmpty ? "无" : app.capabilities.keys.sorted().joined(separator: "、")
                    let detail = """
                    ## \(app.name) v\(app.version)

                    > \(app.description)

                    - **分类**：\(app.category)
                    - **appId**：`\(app.appId)`
                    - **能力**：\(caps)

                    ### 📄 文件清单
                    \(filesList)
                    """
                    self.feedBack(ToolResult(
                        tool: "generate", input: prompt,
                        summary: "生成成功：应用「\(app.name)」v\(app.version)，appId=\(app.appId)，分类=\(app.category)，\(app.files.keys.count) 个文件。用户现在可以说“安装它”等指令。",
                        card: AgentCard(type: "generate",
                                        title: app.name,
                                        subtitle: "v\(app.version) · \(app.category)",
                                        summary: "\(app.description)\n\n生成完成，可“安装它”或继续“修改成…”。",
                                        detail: detail)), round: round)
                case .failure(let err):
                    self.feedBack(ToolResult(tool: "generate", input: prompt,
                                             summary: "打包失败：\(err.localizedDescription)",
                                             card: nil), round: round)
                }
            }
        } catch {
            feedBack(ToolResult(tool: "generate", input: prompt,
                                summary: "解析失败：\(error.localizedDescription)",
                                card: nil), round: round)
        }
    }

    /// iterate：内部调 LLM 修改代码
    private func runIterateTool(instruction: String, round: Int) {
        let targetApp: InstalledApp?
        let files: [String: String]
        let originalPrompt: String

        if let gen = generated, let dir = generatedDir {
            files = loadTextFiles(from: dir)
            targetApp = nil
            originalPrompt = lastPrompt
        } else if let bound = boundApp {
            files = loadTextFiles(from: bound.directory)
            targetApp = bound
            originalPrompt = bound.generationPrompt ?? ""
        } else if let matchedID = matchedInstalledAppID(instruction),
                  let matched = AppLibrary.shared.app(id: matchedID) {
            files = loadTextFiles(from: matched.directory)
            targetApp = matched
            originalPrompt = matched.generationPrompt ?? ""
        } else {
            feedBack(ToolResult(tool: "iterate", input: instruction,
                                summary: "缺少修改目标：请先“生成一个小程序”或告诉我应用名（如“修改待办清单”）。",
                                card: nil), round: round)
            return
        }
        guard !files.isEmpty else {
            feedBack(ToolResult(tool: "iterate", input: instruction,
                                summary: "读取不到目标小程序的代码文件，无法修改。",
                                card: nil), round: round)
            return
        }

        isBusy = true
        let appId = targetApp?.appId ?? generated?.appId ?? "ai.app"
        let version = targetApp?.version ?? generated?.version ?? "1.0.0"

        let client = AIClient()
        currentClient = client
        client.chatStream(
            messages: [
                .init(role: "system", content: AIPrompt.iterateSystem),
                .init(role: "user", content: AIPrompt.iterateUser(
                    originalPrompt: originalPrompt,
                    changeRequest: instruction,
                    currentAppId: appId,
                    currentVersion: version,
                    currentFiles: files
                ))
            ],
            onReasoning: { _ in },
            onDelta: { _ in },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let raw):
                    self.handleIterated(raw: raw, targetApp: targetApp, instruction: instruction, round: round)
                case .failure(let err):
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.feedBack(ToolResult(tool: "iterate", input: instruction,
                                                 summary: "修改失败：\(err.localizedDescription)",
                                                 card: nil), round: round)
                    }
                }
            }
        )
    }

    private func handleIterated(raw: String, targetApp: InstalledApp?, instruction: String, round: Int) {
        do {
            let app = try AIGenerator.parse(raw)
            AIGenerator.writeToDisk(app) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let dir):
                    self.generated = app
                    self.generatedDir = dir
                    let filesList = app.files.keys.sorted()
                        .map { "`\($0)` · \(String(app.files[$0]?.count ?? 0)) 字符" }
                        .joined(separator: "\n")
                    let detail = """
                    ## \(app.name) v\(app.version)（已修改）

                    > \(app.description)

                    - **appId**：`\(app.appId)`（保持不变）

                    ### 📄 当前文件清单
                    \(filesList)
                    """
                    self.feedBack(ToolResult(
                        tool: "iterate", input: instruction,
                        summary: "修改成功：应用「\(app.name)」已升级到 v\(app.version)（appId 不变）。用户可以说“安装”覆盖或“发布”。",
                        card: AgentCard(type: "iterate",
                                        title: app.name,
                                        subtitle: "v\(app.version) · 已修改",
                                        summary: "修改完成，可“安装”覆盖或“发布”到商店。",
                                        detail: detail)), round: round)
                case .failure(let err):
                    self.feedBack(ToolResult(tool: "iterate", input: instruction,
                                             summary: "打包失败：\(err.localizedDescription)",
                                             card: nil), round: round)
                }
            }
        } catch {
            feedBack(ToolResult(tool: "iterate", input: instruction,
                                summary: "解析失败：\(error.localizedDescription)",
                                card: nil), round: round)
        }
    }

    /// publish：异步上传商店
    private func runPublishTool(price: Double, round: Int) {
        if let app = generated, generatedDir != nil,
           AppLibrary.shared.app(id: app.appId) == nil {
            if let dir = generatedDir {
                do {
                    try install(from: app, sourceDir: dir)
                } catch {
                    feedBack(ToolResult(tool: "publish", input: "价格 \(price)",
                                        summary: "发布前安装失败：\(error.localizedDescription)",
                                        card: nil), round: round)
                    return
                }
            }
        }
        guard let installed = AppLibrary.shared.app(id: generated?.appId ?? "") else {
            feedBack(ToolResult(tool: "publish", input: "价格 \(price)",
                                summary: "没有可发布的小程序，请先“生成”并“安装”一个。",
                                card: nil), round: round)
            return
        }
        StorePublisher.shared.publish(app: installed, price: price) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let pub):
                let priceText = pub.price > 0 ? String(format: "售价 ¥%.2f（平台抽成 7%%）", pub.price) : "免费"
                let detail = """
                ## 🚀 已发布 · \(pub.name)

                - **售价**：\(priceText)
                - **版本**：v\(pub.version)
                - **appId**：`\(pub.appId)`

                ### 🔗 源地址（已复制到剪贴板）
                `\(pub.sourceURL)`
                """
                UIPasteboard.general.string = pub.sourceURL
                self.feedBack(ToolResult(
                    tool: "publish", input: "价格 \(price)",
                    summary: "发布成功：应用「\(pub.name)」\(priceText)，源地址 \(pub.sourceURL)（已复制到剪贴板）。",
                    card: AgentCard(type: "publish",
                                    title: pub.name,
                                    subtitle: priceText,
                                    summary: "已上架商店，源地址已复制到剪贴板。",
                                    detail: detail)), round: round)
            case .failure(let err):
                self.feedBack(ToolResult(tool: "publish", input: "价格 \(price)",
                                         summary: "发布失败：\(err.localizedDescription)",
                                         card: nil), round: round)
            }
        }
    }

    /// browse：异步拉商店
    private func browseToolResult(round: Int) {
        guard let token = AuthStore.shared.accessToken else {
            feedBack(ToolResult(tool: "browse", input: "",
                                summary: "浏览商店需要先登录账号（设置 → 账号）。",
                                card: nil), round: round)
            return
        }
        let baseURL: String = {
            if let custom = AppSettings.shared.authServerURL, !custom.isEmpty { return custom }
            return KinterAuthManager.defaultServerURL
        }()
        guard !baseURL.isEmpty, let base = URL(string: baseURL) else {
            feedBack(ToolResult(tool: "browse", input: "",
                                summary: "还没有配置服务器地址（设置 → 账号）。",
                                card: nil), round: round)
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("/api/apps/mine"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let err = err {
                    self.feedBack(ToolResult(tool: "browse", input: "",
                                             summary: "商店连接失败：\(err.localizedDescription)",
                                             card: nil), round: round)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let list = json["apps"] as? [[String: Any]], !list.isEmpty else {
                    self.feedBack(ToolResult(tool: "browse", input: "",
                                             summary: "商店里还没有你发布的应用，可以用“发布，价格 6 元”上架一个。",
                                             card: nil), round: round)
                    return
                }
                let rows = list.compactMap { item -> String? in
                    guard let name = item["name"] as? String else { return nil }
                    let price = (item["price"] as? Double) ?? 0
                    let version = (item["version"] as? String) ?? "1.0.0"
                    let priceText = price > 0 ? String(format: "¥%.2f", price) : "免费"
                    return "### \(name) v\(version)\n\n- **售价**：\(priceText)\n- **下载**：\(item["downloadCount"] as? Int ?? 0) 次"
                }
                self.feedBack(ToolResult(
                    tool: "browse", input: "",
                    summary: "商店共 \(list.count) 个自己发布的应用：\(list.compactMap { $0["name"] as? String }.joined(separator: "、"))",
                    card: AgentCard(type: "browse",
                                    title: "我的商店",
                                    subtitle: "\(list.count) 个已发布",
                                    summary: rows.joined(separator: "\n"),
                                    detail: rows.joined(separator: "\n\n"))), round: round)
            }
        }.resume()
    }

    // MARK: - 同步工具（返回 ToolResult）

    private func installToolResult() -> ToolResult {
        guard let app = generated, let dir = generatedDir else {
            return ToolResult(tool: "install", input: "",
                              summary: "还没有可安装的小程序，请先“生成一个XX小程序”。",
                              card: nil)
        }
        do {
            try install(from: app, sourceDir: dir)
            return ToolResult(
                tool: "install", input: app.name,
                summary: "安装成功：应用「\(app.name)」v\(app.version) 已进入应用库，可以打开或发布。",
                card: AgentCard(type: "install",
                                title: app.name,
                                subtitle: "v\(app.version) · 已安装",
                                summary: "已进入应用库，可“打开它”或“发布，价格 6 元”。",
                                detail: "## \(app.name) v\(app.version)\n\n已安装到应用库 ✅\n\n- **appId**：`\(app.appId)`\n- **分类**：\(app.category)\n- **能力**：\(app.capabilities.isEmpty ? "无" : app.capabilities.keys.sorted().joined(separator: "、"))"))
        } catch {
            return ToolResult(tool: "install", input: app.name,
                              summary: "安装失败：\(error.localizedDescription)",
                              card: nil)
        }
    }

    private func openToolResult(appId: String?) {
        guard let id = appId, let app = AppLibrary.shared.app(id: id) ?? AppLibrary.shared.apps.first(where: { $0.name.contains(appId ?? "") }) else {
            return
        }
        onOpenApp?(app)
    }

    private func listToolResult() -> ToolResult {
        let list = installedListText()
        if list.isEmpty {
            return ToolResult(tool: "list", input: "",
                              summary: "应用库是空的，可以用“做一个XX小程序”开始。",
                              card: nil)
        }
        let apps = AppLibrary.shared.apps
        let detail = apps.map { app in
            let price = app.price ?? 0
            let priceText = price > 0 ? String(format: "¥%.2f", price) : "免费"
            return "### \(app.name) v\(app.version)\n\n- **appId**：`\(app.appId)`\n- **分类**：\(app.category)\n- **售价**：\(priceText)\n- **来源**：\(app.isAIGenerated ? "AI 生成" : "导入")"
        }.joined(separator: "\n\n")
        return ToolResult(
            tool: "list", input: "",
            summary: "应用库共 \(apps.count) 个：\(apps.map(\.name).joined(separator: "、"))",
            card: AgentCard(type: "list",
                            title: "我的小程序",
                            subtitle: "\(apps.count) 个",
                            summary: list,
                            detail: detail))
    }

    private func deleteToolResult(appId: String?) -> ToolResult {
        guard let id = appId, let app = AppLibrary.shared.app(id: id) ?? AppLibrary.shared.apps.first(where: { $0.name.contains(appId ?? "") }) else {
            return ToolResult(tool: "delete", input: appId ?? "",
                              summary: "找不到要删除的小程序「\(appId ?? "")」，它不在应用库里。",
                              card: nil)
        }
        AppLibrary.shared.remove(appId: app.appId)
        NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        return ToolResult(
            tool: "delete", input: app.name,
            summary: "已删除「\(app.name)」（v\(app.version)）。",
            card: AgentCard(type: "delete",
                            title: app.name,
                            subtitle: "已删除",
                            summary: "「\(app.name)」已从应用库移除。",
                            detail: "## 🗑 已删除\n\n`\(app.name)`（v\(app.version)）已从应用库移除。"))
    }

    private func exportToolResult(appId: String?) -> ToolResult {
        let target = appId.flatMap { AppLibrary.shared.app(id: $0) }
            ?? generated.flatMap { AppLibrary.shared.app(id: $0.appId) }
            ?? boundApp
        guard let app = target, let directory = resolveAppDirectory(app) else {
            return ToolResult(tool: "export", input: appId ?? "",
                              summary: "没有可导出的小程序，请先“生成”并“安装”一个。",
                              card: nil)
        }
        do {
            let entries = try loadZipEntries(from: directory)
            let zipData = ZipWriter.build(entries: entries)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(app.name)-v\(app.version).zip")
            try zipData.write(to: tmp)
            let shareVC = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
            if let popover = shareVC.popoverPresentationController {
                popover.sourceView = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first?.keyWindow?.rootViewController?.view
                popover.sourceRect = CGRect(x: 400, y: 400, width: 1, height: 1)
            }
            onPresent?(shareVC)
            return ToolResult(
                tool: "export", input: app.name,
                summary: "已导出「\(app.name)」v\(app.version) 安装包（\(entries.count) 个文件，\(zipData.count) 字节），分享面板已弹出。",
                card: AgentCard(type: "export",
                                title: app.name,
                                subtitle: "v\(app.version) · 已导出",
                                summary: "安装包已生成并弹出分享面板，可直接发送给别人安装。",
                                detail: "## 📦 \(app.name) v\(app.version)\n\n已打包 \(entries.count) 个文件，\(zipData.count) 字节。\n\n可直接通过分享面板发送，对方导入即可运行。"))
        } catch {
            return ToolResult(tool: "export", input: appId ?? "",
                              summary: "导出失败：\(error.localizedDescription)",
                              card: nil)
        }
    }

    private func qrToolResult(text: String) -> ToolResult {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return ToolResult(tool: "qr", input: text,
                              summary: "当前设备不支持二维码生成。",
                              card: nil)
        }
        let clean = text.replacingOccurrences(of: "生成二维码", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(clean.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else {
            return ToolResult(tool: "qr", input: text,
                              summary: "二维码生成失败。",
                              card: nil)
        }
        let scale: CGFloat = 400 / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let image = UIImage(ciImage: scaled)
        let preview = QRPreviewViewController(qrImage: image, content: clean)
        let nav = UINavigationController(rootViewController: preview)
        nav.modalPresentationStyle = .formSheet
        onPresent?(nav)
        return ToolResult(
            tool: "qr", input: clean,
            summary: "已为「\(clean)」生成二维码并弹出预览。",
            card: AgentCard(type: "qr",
                            title: "二维码",
                            subtitle: clean,
                            summary: "已生成二维码预览。",
                            detail: "## 🔳 二维码\n\n内容：\n\n`\(clean)`"))
    }

    private func statsToolResult() -> ToolResult {
        let apps = AppLibrary.shared.apps
        guard !apps.isEmpty else {
            return ToolResult(tool: "stats", input: "",
                              summary: "应用库是空的，可以用“做一个XX小程序”开始。",
                              card: nil)
        }
        let total = apps.count
        let aiCount = apps.filter { $0.isAIGenerated }.count
        let importCount = total - aiCount
        let categories = Dictionary(grouping: apps, by: { $0.category }).mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .map { "- \($0.key)：\($0.value) 个" }.joined(separator: "\n")
        let paidCount = apps.filter { ($0.price ?? 0) > 0 }.count
        let detail = """
        ## 📊 应用库统计

        - **总数**：\(total) 个
        - **AI 生成**：\(aiCount) 个
        - **手动导入**：\(importCount) 个
        - **已定价**：\(paidCount) 个

        ### 分类分布
        \(categories)
        """
        return ToolResult(
            tool: "stats", input: "",
            summary: "统计：共 \(total) 个应用，AI \(aiCount) / 导入 \(importCount) / 付费 \(paidCount)。",
            card: AgentCard(type: "stats",
                            title: "应用库统计",
                            subtitle: "\(total) 个应用",
                            summary: "AI 生成 \(aiCount) · 导入 \(importCount) · 付费 \(paidCount)",
                            detail: detail))
    }

    // MARK: - 收尾 / 取消

    private func completeAction() {
        isBusy = false
        currentClient = nil
        if !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            lastPrompt = next
            startAgent(round: 0)
        }
        onUpdate?()
    }

    func cancel() {
        currentClient?.cancel()
        closeStreamingBubble()
        completeAction()
    }

    private func closeStreamingBubble() {
        for i in messages.indices where messages[i].role == "agent" && messages[i].isStreaming {
            messages[i].isStreaming = false
        }
    }

    // MARK: - 工具执行记录（回灌）

    private func recordTool(tool: String, input: String, result: String) {
        toolHistory.append(ToolCallRecord(tool: tool, input: input, result: result))
        if toolHistory.count > 30 { toolHistory.removeFirst(toolHistory.count - 30) }
    }

    func toolHistoryText() -> String {
        guard !toolHistory.isEmpty else { return "" }
        let rows = toolHistory.map { "- `\($0.tool)`(输入：\($0.input)) → \($0.result)" }
            .joined(separator: "\n")
        return "\n\n# 本会话已执行的工具记录（真实发生，可用于回答用户追问）\n\(rows)"
    }

    // MARK: - 工具方法

    private func install(from app: AIGenerator.GeneratedApp, sourceDir: URL) throws {
        let iconPath = sourceDir.appendingPathComponent("icon.png")
        let hasIcon = FileManager.default.fileExists(atPath: iconPath.path)
        let installed = InstalledApp(
            appId: app.appId,
            name: app.name,
            version: app.version,
            installedAt: Date(),
            category: app.category,
            disabledCapabilities: [],
            iconFileName: hasIcon ? "icon.png" : nil,
            isAIGenerated: true,
            generationPrompt: lastPrompt
        )
        let dest = installed.directory
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                let rel = fileURL.path.replacingOccurrences(of: sourceDir.path, with: "")
                let target = dest.appendingPathComponent(rel)
                if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    try? fm.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                    try fm.copyItem(at: fileURL, to: target)
                }
            }
        }
        AppLibrary.shared.add(installed)
        installed.ensureDataDirectory()
        NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
    }

    private func resolveAppDirectory(_ app: InstalledApp) -> URL? {
        if let dir = generatedDir, generated?.appId == app.appId { return dir }
        return app.directory
    }

    private func loadZipEntries(from dir: URL) throws -> [ZipWriter.Entry] {
        var entries: [ZipWriter.Entry] = []
        let fm = FileManager.default
        guard let files = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        for case let file as URL in files where !file.hasDirectoryPath {
            let rel = file.path.replacingOccurrences(of: dir.path + "/", with: "")
            let data = try Data(contentsOf: file)
            entries.append(.init(path: rel, data: data))
        }
        return entries
    }

    private func loadTextFiles(from dir: URL) -> [String: String] {
        var result: [String: String] = [:]
        let fm = FileManager.default
        let textExts: Set<String> = ["html", "htm", "css", "js", "svg", "json", "txt", "xml"]
        guard let enumerator = fm.enumerator(at: dir,
                                             includingPropertiesForKeys: [.isRegularFileKey]) else {
            return result
        }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard textExts.contains(ext) else { continue }
            if url.lastPathComponent == "manifest.json" { continue }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            if let size = attrs?[.size] as? Int, size > 200_000 { continue }
            let rel = url.path.replacingOccurrences(of: dir.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !rel.isEmpty else { continue }
            if let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                result[rel] = s
            }
        }
        return result
    }

    private func matchedInstalledAppID(_ text: String) -> String? {
        let apps = AppLibrary.shared.apps
        for app in apps where text.contains(app.appId) { return app.appId }
        for app in apps where text.contains(app.name) { return app.appId }
        return nil
    }

    private func installedListText() -> String {
        let apps = AppLibrary.shared.apps
        guard !apps.isEmpty else { return "" }
        return apps.map { "• \($0.name)（\($0.version)）\($0.paid || ($0.price ?? 0) <= 0 ? "" : "· ¥\(String(format: "%.2f", $0.price ?? 0)) 未解锁")" }
            .joined(separator: "\n")
    }

    // MARK: - 消息工具

    private func streamAppend(bubbleIdx: Int?, text: String) {
        guard !text.isEmpty else { return }
        if let idx = messages.lastIndex(where: { $0.role == "agent" && $0.isStreaming && !$0.isToolCallFrame }) {
            messages[idx].text += text
        }
        onStream?(text)
        onUpdate?()
    }

    private func appendAgent(_ text: String, card: AgentCard? = nil) {
        messages.append(ChatMessage(role: "agent", text: text, isStreaming: false, card: card))
    }
}
