import Foundation
import UIKit

/// Kinter AI Agent：对话式小程序管理器。
/// 用户用自然语言指挥它：生成、修改、安装、发布、打开、删除小程序。
final class AgentRuntime {

    // MARK: - 会话消息

    struct ChatMessage {
        let role: String        // user / agent / system
        var text: String
        var isStreaming: Bool   // 是否正在流式输出
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
        case help
        case needTarget(what: String)     // 需要指定目标小程序
    }

    // MARK: - 状态

    private(set) var messages: [ChatMessage] = []
    private(set) var isBusy = false

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
        guard !isBusy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(ChatMessage(role: "user", text: trimmed, isStreaming: false))
        onUpdate?()
        lastPrompt = trimmed

        switch routeIntent(trimmed) {
        case .help:
            appendAgent(helpText)
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
        case .needTarget(let what):
            appendAgent("需要告诉我操作哪个小程序。当前已装：\n" + installedListText() +
                        "\n\n或者先让我“生成一个小程序”。（你想\(what)）")
        }
    }

    func cancel() {
        currentClient?.cancel()
        if let idx = messages.lastIndex(where: { $0.role == "agent" && $0.isStreaming }) {
            messages[idx].isStreaming = false
        }
        isBusy = false
        onUpdate?()
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
            if generated != nil || boundApp != nil {
                return .iterate(instruction: text)
            }
            if let id = matchedInstalledAppID(text) {
                return .iterate(instruction: text)
            }
            return .iterate(instruction: text)
        }
        // 默认：当作生成请求
        return .generate(prompt: text)
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
                .init(role: "system", content: AIPrompt.system),
                .init(role: "user", content: AIPrompt.user(prompt))
            ],
            onReasoning: { [weak self] chunk in
                guard let self = self else { return }
                self.streamAppend(bubbleIdx: nil, text: "")
                _ = chunk
            },
            onDelta: { [weak self] chunk in
                self?.streamAppend(bubbleIdx: nil, text: chunk)
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.currentClient = nil
                self.isBusy = false
                switch result {
                case .success(let raw):
                    self.handleGenerated(raw: raw, prompt: prompt)
                case .failure(let err):
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.appendAgent("⚠️ 生成失败：\(err.localizedDescription)")
                    }
                }
                self.onUpdate?()
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
                    self.appendAgent("✅ 已生成「\(app.name)」（v\(app.version)）\n"
                        + "\(app.description)\n\n"
                        + "接下来你可以：\n"
                        + "  1. “安装它”\n"
                        + "  2. “修改成…”（继续改）\n"
                        + "  3. “发布，价格 6 元”")
                case .failure(let err):
                    self.appendAgent("⚠️ 打包失败：\(err.localizedDescription)")
                }
                self.onUpdate?()
            }
        } catch {
            appendAgent("⚠️ 解析失败：\(error.localizedDescription)")
            onUpdate?()
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
                ))
            ],
            onReasoning: { [weak self] _ in self?.streamAppend(bubbleIdx: nil, text: "") },
            onDelta: { [weak self] chunk in self?.streamAppend(bubbleIdx: nil, text: chunk) },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.currentClient = nil
                self.isBusy = false
                switch result {
                case .success(let raw):
                    self.handleIterated(raw: raw, targetApp: targetApp)
                case .failure(let err):
                    if case AIClient.AIError.cancelled = err {
                        self.cancel()
                    } else {
                        self.appendAgent("⚠️ 修改失败：\(err.localizedDescription)")
                    }
                }
                self.onUpdate?()
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
                    self.appendAgent("✅ 已按你的要求修改「\(app.name)」。\n\n"
                        + "要“安装”覆盖原应用，或“发布”到商店吗？")
                case .failure(let err):
                    self.appendAgent("⚠️ 打包失败：\(err.localizedDescription)")
                }
                self.onUpdate?()
            }
        } catch {
            appendAgent("⚠️ 解析失败：\(error.localizedDescription)")
            onUpdate?()
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
            appendAgent("📦 已安装到应用库：「\(app.name)」。\n\n"
                + "可以“打开它”，或“发布，价格 6 元”上架到商店。")
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
                self.appendAgent("🚀 已发布「\(pub.name)」，\(priceText)。\n源地址：\(pub.sourceURL)\n已复制到剪贴板。")
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
        appendAgent(list.isEmpty ? "应用库还是空的。对我说“做一个XX小程序”开始吧。"
                                 : "📱 你当前有这些小程序：\n\(list)")
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
        appendAgent("🗑 已删除「\(app.name)」。")
        onUpdate?()
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
        "我可以帮你管理小程序，试试这样说：\n\n"
        + "• 生成：\"做一个番茄钟小程序，红色主题\"\n"
        + "• 修改：\"把主题改成深色\" / \"加一个计时功能\"\n"
        + "• 安装：\"安装它\"\n"
        + "• 发布：\"发布到商店，价格 6 元\"\n"
        + "• 打开：\"打开番茄钟\"\n"
        + "• 列表：\"有哪些小程序\"\n"
        + "• 删除：\"删除番茄钟\""
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

    private func appendAgent(_ text: String) {
        messages.append(ChatMessage(role: "agent", text: text, isStreaming: false))
    }
}
