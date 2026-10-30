# 崩溃防护与稳定性

## 三条铁律

### 1. 同步异常隔离
网关对每个 Provider 调用都包 `ObjCExceptionCatcher`。任何 ObjC 异常降级为 `provider_error`，不拖垮宿主。

例：HealthKit 缺 entitlement 时会抛 ObjC 异常，被隔离后返回 `unsupported` 而非崩溃。

### 2. 异步异常自捕获
网关捕获不到异步回调里的异常，**Provider 内部必须自行包一层**。

例：SpeechProvider 的 `installTap` 音频回调。

### 3. UIKit 呈现安全
**iPad 上 popover 必须指定 `sourceView`**，否则呈现动画中抛异常崩溃。

统一走 `UIViewController+SafelyPresent.swift` 扩展，自动设置锚点。

## 模拟器限制

| 能力 | 模拟器表现 |
|---|---|
| 相机 | 无摄像头，返回 `unsupported` |
| 麦克风 | 无输入设备，采样率 0，预检返回 `unsupported` |
| Face ID | 无硬件，直接 `unsupported` |
| 定位 | 返回旧金山默认坐标 |
| 实时活动 | 不可用 |
| 健康 | 需真机 + entitlement |
| badQuery | 无 `libsystem_containermanager.dylib`，探测返回 -1 |

这些都会优雅降级，不会崩溃。

## 超时保护

- **桥接层**：统一 30 秒超时，超时 Promise 以 `{code:'timeout'}` 拒绝
- **AI 流式**：90 秒无数据自动中断（空闲看门狗）
- **HTTP**：默认 30s，上限 60s

## 批量自测

示例小程序里有「runAll」按钮，依次调用 16 项无交互/低风险能力，每项 3 秒超时，最后汇总成 ✓/✗ 表格。用于一键回归验证网关链路。

## 内存与性能

- 每个小程序会话独立 Gateway + Provider，退出时随会话销毁
- 事件批量推送：同一 RunLoop 内多次 emit 合并为一次 `evaluateJavaScript`
- 长列表分页，不一次性渲染上千条
