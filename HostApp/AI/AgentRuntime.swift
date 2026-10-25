import Foundation
import UIKit

/// Kinter AI Agent：对话式小程序管理器。
/// 用户用自然语言指挥它：生成、修改、安装、发布、打开、删除小程序。
final class AgentRuntime {

    // MARK: - 会话消息

    /// 工具执行结果卡片（点击可查看详细信息）
    struct AgentCard {
        let type: String      // generate / iterate / install / publish / list / delete / open
        let title: String     // 卡片标题（如应用名）
        let subtitle: String  // 副标题（版本/价格等）
        let summary: String   // 卡片正文摘要（支持 Markdown）
        let detail: String    // 详情（点击展开，支持 Markdown）
    }

    struct ChatMessage {
        let role: String        // user / agent / system
        var text: String
        var isStreaming: Bool   // 是否正在流式输出
        var card: AgentCard?    // 工具执行结果卡片（有值则 UI 渲染成卡片）
    }

    // MARK: - 意图（规则路由结果）

    enum Action {
        case generate(prompt: String)
        case iterate(instruction: String)
        case install
        case publish(price: Double)
        case open(appId: String)
        case list
        case delete(appId: String)
        case export(appId: String?)      // 导出/分享小程序包（zip）
        case qr(text: String)            // 生成二维码
        case stats                       // 应用库统计
        case browse                      // 商店浏览（我的已发布）
        case help
        case chat(text: String)          // 非管理意图：正常聊天
        case needTarget(what: String)    // 需要指定目标小程序
    }

    /// 工具执行记录（回灌给 AI：后续对话能感知执行过什么）
    struct ToolCallRecord {
        let tool: String      // 工具名（generate/install/publish/...）
        let input: String     // 输入摘要
        let result: String    // 结果摘要
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

    init(boundApp: InstalledApp? = nil) {
        self.boundApp = boundApp
        var opener = "我是你的小程序 AI 助手，可以用一句话为你生成、修改、安装、发布、打开或删除小程序。"
        if let app = boundApp {
            opener += "\n\n当前正在处理小程序「\(app.name)」（v\(app.version)），你可以直接说“把主题改成深色”“加一个计时功能”等。"
        }
        messages = [
            ChatMessage(role: "agent", text: opener, isStreaming: false)
        ]
    }

    // MARK: - 发送

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
        execute(routeIntent(trimmed))
    }

    /// 执行路由后的动作（异步动作会置 busy）
    private func execute(_ action: Action) {
        switch action {
        case .help:
            appendAgent(helpText)
            onUpdate?()
        case .generate(let prompt):
            runGenerate(prompt: prompt)
        case .iterate(let instruction):
            runIterate(instruction: instruction)
        case .install:
            runInstall()
        case .publish(let price):
            runPublish(price: price)
        case .open(let appId):
            runOpen(appId: appId)
        case .list:
            runList()
        case .delete(let appId):
            runDelete(appId: appId)
        case .export(let appId):
            runExport(appId: appId)
        case .qr(let text):
            runQR(text: text)
        case .stats:
            runStats()
        case .browse:
            runBrowse()
        case .needTarget(let what):
            appendAgent("需要告诉我操作哪个小程序。当前已装：\n" + installedListText() +
                        "\n\n或者先让我“生成一个小程序”。（你想\(what)）")
            onUpdate?()
        case .chat(let text):
            runChat(text: text)
        }
    }

    /// 异步动作完成后统一收尾：复位 busy + 接续排队消息
    private func completeAction() {
        isBusy = false
        currentClient = nil
        if !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            lastPrompt = next
            execute(routeIntent(next))
        }
        onUpdate?()
    }

    func cancel() {
        currentClient?.cancel()
        closeStreamingBubble()
        completeAction()
    }

    /// 关闭所有流式气泡（输出完成/取消时调用，避免 ▋ 光标残留）
    private func closeStreamingBubble() {
        for i in messages.indices where messages[i].role == "agent" && messages[i].isStreaming {
            messages[i].isStreaming = false
        }
    }

    // MARK: - 意图路由（规则版）

    func routeIntent(_ text: String) -> Action {
        // 帮助
        if containsAny(text, ["帮助", "能做什么", "你会什么", "你是谁", "介绍"]) {
            return .help
        }
        // 删除/卸载
        if containsAny(text, ["删除", "卸载", "移除"]) {
            if let id = matchedInstalledAppID(text) {
                return .delete(appId: id)
            }
            return .needTarget(what: "删除")
        }
        // 打开/运行
        if containsAny(text, ["打开", "运行", "启动"]) {
            if let id = matchedInstalledAppID(text) {
                return .open(appId: id)
            }
            return .needTarget(what: "打开")
        }
        // 导出/打包/分享
        if containsAny(text, ["导出", "打包", "下载", "备份", "导出到"]) {
            return .export(appId: matchedInstalledAppID(text))
        }
        // 二维码
        if containsAny(text, ["二维码", "扫码", "qr"]) {
            let target = matchedInstalledAppID(text)
            if let app = AppLibrary.shared.apps.first(where: { $0.appId == target ?? "" }) {
                return .qr(text: "Kinter 小程序「\(app.name)」\nappId: \(app.appId)")
            }
            return .qr(text: text)
        }
        // 统计
        if containsAny(text, ["统计", "数据报告", "有几个小程序", "分类分布", "库存"]) {
            return .stats
        }
        // 商店/上架浏览
        if containsAny(text, ["商店", "商城", "看看市场", "市场里", "已发布的应用", "我发布的"]) {
            return .browse
        }
        // 列表
        if containsAny(text, ["有哪些", "列表", "看看我的", "我的小程序", "查看应用", "几个小程序"]) {
            return .list
        }
        // 安装/导入
        if containsAny(text, ["安装", "导入", "装进", "装到", "装上"]) {
            return .install
        }
        // 发布/上架
        if containsAny(text, ["发布", "上架", "出售", "卖"]) {
            return .publish(price: extractPrice(text))
        }
        // 修改/迭代（有对象时）
        if containsAny(text, ["改成", "修改", "变成", "换个", "加上", "添加", "优化", "改一下", "换一个",
                              "增加", "删掉", "红色", "蓝色", "主题", "风格", "界面", "功能"]) {
            if generated != nil || boundApp != nil || matchedInstalledAppID(text) != nil {
                return .iterate(instruction: text)
            }
            return .chat(text: text)
        }
        // 明确生成意图：生成动词 / 提到小程序且是需求描述
        let genVerbs = ["生成", "做一个", "帮我做", "帮我弄", "写一个", "创建一个", "开发一个",
                        "搞一个", "来个", "做个", "想要一个", "我想要", "能不能做一个", "给我做",
                        "弄一个", "做个小程序", "写个小程序", "生成一个"]
        if containsAny(text, genVerbs) {
            return .generate(prompt: text)
        }
        if text.contains("小程序") && text.count > 6 {
            return .generate(prompt: text)
        }
        // 其余：正常聊天
        return .chat(text: text)
    }

    /// 纯聊天：流式回复，不触发小程序动作
    private func runChat(text: String) {
        isBusy = true
        let bubble = ChatMessage(role: "agent", text: "", isStreaming: true)
        messages.append(bubble)
        onUpdate?()

        let client = AIClient()
        currentClient = client
        client.chatStream(
            messages: [
                .init(role: "system", content: AIPrompt.chatSystem(installed: installedListText())
                    + toolHistoryText()
                    + "\n\n# 可用工具\n" + AIPrompt.toolCatalog),
                .init(role: "user", content: text)
            ],
            onReasoning: { [weak self] _ in self?.onUpdate?() },
            onDelta: { [weak self] chunk in self?.streamAppend(bubbleIdx: nil, text: chunk) },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.closeStreamingBubble()
                switch result {
                case .success:
                    break
                case .failure(let err):
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.appendAgent("⚠️ 回复失败：\(err.localizedDescription)")
                    }
                }
                self.completeAction()
            }
        )
    }

    // MARK: - 动作执行

    /// 生成新小程序（流式）
    private func runGenerate(prompt: String) {
        isBusy = true
        let bubble = ChatMessage(role: "agent", text: "", isStreaming: true)
        messages.append(bubble)
        onUpdate?()

        let client = AIClient()
        currentClient = client
        client.chatStream(
            messages: [
                .init(role: "system", content: AIPrompt.system + toolHistoryText() + "\n\n# 可用工具\n" + AIPrompt.toolCatalog),
                .init(role: "user", content: AIPrompt.user(prompt))
            ],
            onReasoning: { [weak self] _ in self?.onUpdate?() },
            onDelta: { [weak self] chunk in
                self?.streamAppend(bubbleIdx: nil, text: chunk)
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let raw):
                    self.closeStreamingBubble()
                    self.handleGenerated(raw: raw, prompt: prompt)
                case .failure(let err):
                    self.closeStreamingBubble()
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.appendAgent("⚠️ 生成失败：\(err.localizedDescription)")
                        self.completeAction()
                    }
                }
            }
        )
    }

    private func handleGenerated(raw: String, prompt: String) {
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
                    self.appendAgent("✅ 已生成「\(app.name)」，随时可以安装或继续修改。",
                                     card: AgentCard(type: "generate",
                                                     title: app.name,
                                                     subtitle: "v\(app.version) · \(app.category)",
                                                     summary: "\(app.description)\n\n生成完成，可“安装它”或继续“修改成…”。",
                                                     detail: detail))
                    self.recordTool(tool: "generate", input: prompt,
                                    result: "生成了「\(app.name)」(v\(app.version), appId=\(app.appId), 分类=\(app.category), 文件=\(app.files.keys.count) 个)")
                case .failure(let err):
                    self.appendAgent("⚠️ 打包失败：\(err.localizedDescription)")
                }
                self.completeAction()
            }
        } catch {
            appendAgent("⚠️ 解析失败：\(error.localizedDescription)")
            completeAction()
        }
    }

    /// 迭代修改（当前生成的 or 绑定的已装小程序）
    private func runIterate(instruction: String) {
        // 确定目标：优先当前生成，其次绑定应用，其次匹配已装
        let targetApp: InstalledApp?
        let files: [String: String]
        let originalPrompt: String

        if let gen = generated, let dir = generatedDir {
            // 迭代当前生成：读生成目录
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
            appendAgent("我不知道要改哪个小程序。可以先说“生成一个小程序”，或者指定名字（如“修改待办清单”）。")
            onUpdate?()
            return
        }

        guard !files.isEmpty else {
            appendAgent("⚠️ 读取不到目标小程序的代码文件，无法修改。")
            onUpdate?()
            return
        }

        isBusy = true
        let bubble = ChatMessage(role: "agent", text: "", isStreaming: true)
        messages.append(bubble)
        onUpdate?()

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
                ) + toolHistoryText()),
            ],
            onReasoning: { [weak self] _ in self?.onUpdate?() },
            onDelta: { [weak self] chunk in self?.streamAppend(bubbleIdx: nil, text: chunk) },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let raw):
                    self.closeStreamingBubble()
                    self.handleIterated(raw: raw, targetApp: targetApp)
                case .failure(let err):
                    self.closeStreamingBubble()
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.appendAgent("⚠️ 修改失败：\(err.localizedDescription)")
                        self.completeAction()
                    }
                }
            }
        )
    }

    private func handleIterated(raw: String, targetApp: InstalledApp?) {
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
                    self.appendAgent("✅ 已按你的要求修改「\(app.name)」（v\(app.version)）。",
                                     card: AgentCard(type: "iterate",
                                                     title: app.name,
                                                     subtitle: "v\(app.version) · 已修改",
                                                     summary: "修改完成，可“安装”覆盖或“发布”到商店。",
                                                     detail: detail))
                    self.recordTool(tool: "iterate", input: targetApp?.name ?? app.name,
                                    result: "修改了「\(app.name)」到 v\(app.version)（appId=\(app.appId)）")
                case .failure(let err):
                    self.appendAgent("⚠️ 打包失败：\(err.localizedDescription)")
                }
                self.completeAction()
            }
        } catch {
            appendAgent("⚠️ 解析失败：\(error.localizedDescription)")
            completeAction()
        }
    }

    // MARK: - 安装 / 发布 / 打开 / 列表 / 删除

    private func runInstall() {
        guard let app = generated, let dir = generatedDir else {
            appendAgent("还没有可安装的小程序。先告诉我“做一个XX小程序”。")
            onUpdate?()
            return
        }
        do {
            try install(from: app, sourceDir: dir)
            appendAgent("📦 已安装「\(app.name)」，可以打开或发布。",
                        card: AgentCard(type: "install",
                                        title: app.name,
                                        subtitle: "v\(app.version) · 已安装",
                                        summary: "已进入应用库，可“打开它”或“发布，价格 6 元”。",
                                        detail: "## \(app.name) v\(app.version)\n\n已安装到应用库 ✅\n\n- **appId**：`\(app.appId)`\n- **分类**：\(app.category)\n- **能力**：\(app.capabilities.isEmpty ? "无" : app.capabilities.keys.sorted().joined(separator: "、"))"))
            self.recordTool(tool: "install", input: app.name,
                            result: "安装了「\(app.name)」v\(app.version) 到应用库")
        } catch {
            appendAgent("⚠️ 安装失败：\(error.localizedDescription)")
        }
        onUpdate?()
    }

    private func runPublish(price: Double) {
        // 确保已安装
        if let app = generated, generatedDir != nil,
           AppLibrary.shared.app(id: app.appId) == nil {
            if let dir = generatedDir {
                do {
                    try install(from: app, sourceDir: dir)
                } catch {
                    appendAgent("⚠️ 发布前安装失败：\(error.localizedDescription)")
                    onUpdate?()
                    return
                }
            }
        }
        guard let installed = AppLibrary.shared.app(id: generated?.appId ?? "") else {
            appendAgent("没有可发布的小程序。先“生成”并“安装”一个。")
            onUpdate?()
            return
        }
        // 未登录时由 StorePublisher 自己提示
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
                self.appendAgent("🚀 已发布「\(pub.name)」，\(priceText)。源地址已复制。",
                                 card: AgentCard(type: "publish",
                                                 title: pub.name,
                                                 subtitle: priceText,
                                                 summary: "已上架商店，源地址已复制到剪贴板。",
                                                 detail: detail))
                self.recordTool(tool: "publish", input: "价格 \(price)",
                                result: "发布了「\(pub.name)」\(priceText)，源地址 \(pub.sourceURL)")
                UIPasteboard.general.string = pub.sourceURL
            case .failure(let err):
                self.appendAgent("⚠️ 发布失败：\(err.localizedDescription)")
            }
            self.onUpdate?()
        }
    }

    private func runOpen(appId: String) {
        guard let app = AppLibrary.shared.app(id: appId) else {
            appendAgent("找不到「\(appId)」，它不在应用库里。")
            onUpdate?()
            return
        }
        appendAgent("正在打开「\(app.name)」…")
        onUpdate?()
        onOpenApp?(app)
    }

    private func runList() {
        let list = installedListText()
        if list.isEmpty {
            appendAgent("应用库还是空的。对我说“做一个XX小程序”开始吧。")
        } else {
            let apps = AppLibrary.shared.apps
            let detail = apps.map { app in
                let price = app.price ?? 0
                let priceText = price > 0 ? String(format: "¥%.2f", price) : "免费"
                return "### \(app.name) v\(app.version)\n\n- **appId**：`\(app.appId)`\n- **分类**：\(app.category)\n- **售价**：\(priceText)\n- **来源**：\(app.isAIGenerated ? "AI 生成" : "导入")"
            }.joined(separator: "\n\n")
            appendAgent("📱 你当前有 \(apps.count) 个小程序：\n\(list)",
                        card: AgentCard(type: "list",
                                        title: "我的小程序",
                                        subtitle: "\(apps.count) 个",
                                        summary: list,
                                        detail: detail))
            recordTool(tool: "list", input: "", result: "应用库共 \(apps.count) 个：\(apps.map(\.name).joined(separator: "、"))")
        }
        onUpdate?()
    }

    private func runDelete(appId: String) {
        guard let app = AppLibrary.shared.app(id: appId) else {
            appendAgent("找不到「\(appId)」，它不在应用库里。")
            onUpdate?()
            return
        }
        AppLibrary.shared.remove(appId: appId)
        NotificationCenter.default.post(name: .appLibraryDidChange, object: nil)
        appendAgent("🗑 已删除「\(app.name)」。",
                    card: AgentCard(type: "delete",
                                    title: app.name,
                                    subtitle: "已删除",
                                    summary: "「\(app.name)」已从应用库移除。",
                                    detail: "## 🗑 已删除\n\n`\(app.name)`（v\(app.version)）已从应用库移除。"))
        recordTool(tool: "delete", input: app.name, result: "删除了「\(app.name)」(v\(app.version))")
        onUpdate?()
    }

    // MARK: - 新工具：导出 / 二维码 / 统计 / 商店浏览

    /// 导出：把小程序打包 zip 分享（系统分享面板）
    private func runExport(appId: String?) {
        let target = appId.flatMap { AppLibrary.shared.app(id: $0) }
            ?? generated.flatMap { AppLibrary.shared.app(id: $0.appId) }
            ?? boundApp
        guard let app = target, let directory = resolveAppDirectory(app) else {
            appendAgent("没有可导出的小程序。先“生成”并“安装”一个。")
            onUpdate?()
            return
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
            recordTool(tool: "export", input: app.name, result: "导出 \(app.name) v\(app.version)，\(entries.count) 个文件，\(zipData.count) 字节")
            appendAgent("📦 已导出「\(app.name)」安装包（\(entries.count) 个文件），分享面板已弹出。",
                        card: AgentCard(type: "export",
                                        title: app.name,
                                        subtitle: "v\(app.version) · 已导出",
                                        summary: "安装包已生成并弹出分享面板，可直接发送给别人安装。",
                                        detail: "## 📦 \(app.name) v\(app.version)\n\n已打包 \(entries.count) 个文件，\(zipData.count) 字节。\n\n可直接通过分享面板发送，对方导入即可运行。"))
        } catch {
            appendAgent("⚠️ 导出失败：\(error.localizedDescription)")
        }
        onUpdate?()
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

    /// 二维码：为文本生成二维码图片并弹出预览
    private func runQR(text: String) {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            appendAgent("⚠️ 当前设备不支持二维码生成。")
            onUpdate?()
            return
        }
        let clean = text.replacingOccurrences(of: "生成二维码", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(clean.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else {
            appendAgent("⚠️ 二维码生成失败。")
            onUpdate?()
            return
        }
        // 放大（原图太小）
        let scale: CGFloat = 400 / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let image = UIImage(ciImage: scaled)

        let preview = QRPreviewViewController(qrImage: image, content: clean)
        let nav = UINavigationController(rootViewController: preview)
        nav.modalPresentationStyle = .formSheet
        onPresent?(nav)
        recordTool(tool: "qr", input: clean, result: "为「\(clean)」生成了二维码")
        appendAgent("🔳 二维码已生成，请扫码查看。",
                    card: AgentCard(type: "qr",
                                    title: "二维码",
                                    subtitle: clean,
                                    summary: "已生成二维码预览。",
                                    detail: "## 🔳 二维码\n\n内容：\n\n`\(clean)`"))
        onUpdate?()
    }

    /// 统计：应用库统计报告
    private func runStats() {
        let apps = AppLibrary.shared.apps
        guard !apps.isEmpty else {
            appendAgent("应用库还是空的，先“做一个XX小程序”吧。")
            onUpdate?()
            return
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
        recordTool(tool: "stats", input: "", result: "共 \(total) 个应用：AI \(aiCount) / 导入 \(importCount) / 付费 \(paidCount)")
        appendAgent("📊 统计完成，共 \(total) 个小程序。",
                    card: AgentCard(type: "stats",
                                    title: "应用库统计",
                                    subtitle: "\(total) 个应用",
                                    summary: "AI 生成 \(aiCount) · 导入 \(importCount) · 付费 \(paidCount)",
                                    detail: detail))
        onUpdate?()
    }

    /// 商店浏览：拉取我已发布的应用列表
    private func runBrowse() {
        guard let token = AuthStore.shared.accessToken else {
            appendAgent("浏览商店需要先登录账号。打开「设置 → 账号」登录后再说“看看商店”。")
            onUpdate?()
            return
        }
        let baseURL = {
            if let custom = AppSettings.shared.authServerURL, !custom.isEmpty {
                return custom
            }
            return KinterAuthManager.defaultServerURL
        }()
        guard !baseURL.isEmpty else {
            appendAgent("还没有配置服务器地址。打开「设置 → 账号」填写服务器。")
            onUpdate?()
            return
        }
        guard let base = URL(string: baseURL) else {
            appendAgent("服务器地址无效，请到「设置 → 账号」检查。")
            onUpdate?()
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
                    self.appendAgent("⚠️ 商店连接失败：\(err.localizedDescription)")
                    self.onUpdate?()
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let list = json["apps"] as? [[String: Any]], !list.isEmpty else {
                    self.appendAgent("商店里还没有你发布的应用。对我说“发布，价格 6 元”试试。")
                    self.onUpdate?()
                    return
                }
                let rows = list.compactMap { item -> String? in
                    guard let name = item["name"] as? String else { return nil }
                    let price = (item["price"] as? Double) ?? 0
                    let version = (item["version"] as? String) ?? "1.0.0"
                    let priceText = price > 0 ? String(format: "¥%.2f", price) : "免费"
                    return "### \(name) v\(version)\n\n- **售价**：\(priceText)\n- **下载**：\(item["downloadCount"] as? Int ?? 0) 次"
                }
                self.appendAgent("🏪 商店里你发布了 \(list.count) 个应用：\n\(rows.joined(separator: "\n\n"))",
                                 card: AgentCard(type: "browse",
                                                 title: "我的商店",
                                                 subtitle: "\(list.count) 个已发布",
                                                 summary: rows.joined(separator: "\n"),
                                                 detail: rows.joined(separator: "\n\n")))
                self.recordTool(tool: "browse", input: "", result: "商店里有 \(list.count) 个自己发布的应用")
                self.onUpdate?()
            }
        }.resume()
    }

    /// 记录工具执行结果（回灌给 AI 上下文）
    private func recordTool(tool: String, input: String, result: String) {
        toolHistory.append(ToolCallRecord(tool: tool, input: input, result: result))
        if toolHistory.count > 30 { toolHistory.removeFirst(toolHistory.count - 30) }
    }

    /// 工具历史文本（注入 LLM 上下文，让 AI 感知执行过的工具与结果）
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
        // 优先名字/ID 精确子串匹配
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

    private func extractPrice(_ text: String) -> Double {
        var t = text
        if let range = t.range(of: "价格") { t = String(t[range.upperBound...]) }
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(match.range(at: 1), in: t),
              let price = Double(t[r]) else { return 0 }
        return price
    }

    private func containsAny(_ text: String, _ keys: [String]) -> Bool {
        keys.contains { text.contains($0) }
    }

    private var helpText: String {
        "我是你的小程序 AI 管家，一共有 **10 个工具**，试试这样说：\n\n"
        + "🛠 **生成**：\"做一个番茄钟小程序，红色主题\"\n"
        + "✏️ **修改**：\"把主题改成深色\" / \"加一个计时功能\"\n"
        + "📦 **安装**：\"安装它\"\n"
        + "🚀 **发布**：\"发布到商店，价格 6 元\"\n"
        + "▶️ **打开**：\"打开番茄钟\"\n"
        + "📱 **列表**：\"有哪些小程序\"\n"
        + "🗑 **删除**：\"删除番茄钟\"\n"
        + "💾 **导出**：\"导出番茄钟\"（打包 zip 分享给别人）\n"
        + "🔳 **二维码**：\"给番茄钟生成二维码\"\n"
        + "📊 **统计**：\"统计一下\"（应用库数据报告）\n"
        + "🏪 **商店**：\"看看商店\"（我发布的应用）"
    }

    // MARK: - 消息工具

    private func streamAppend(bubbleIdx: Int?, text: String) {
        guard !text.isEmpty else { return }
        if let idx = messages.lastIndex(where: { $0.role == "agent" && $0.isStreaming }) {
            messages[idx].text += text
        }
        onStream?(text)
        onUpdate?()
    }

    private func appendAgent(_ text: String, card: AgentCard? = nil) {
        messages.append(ChatMessage(role: "agent", text: text, isStreaming: false, card: card))
    }
}
