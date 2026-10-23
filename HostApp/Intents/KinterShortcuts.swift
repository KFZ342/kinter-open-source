import AppIntents

/// 向系统注册所有 Intent。
struct KinterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenMiniAppIntent(),
            phrases: [
                "用 \(.applicationName) 打开小程序",
                "在 \(.applicationName) 里运行小程序"
            ],
            shortTitle: "打开小程序",
            systemImageName: "square.stack"
        )
    }
}
