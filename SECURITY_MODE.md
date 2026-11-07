# Kinter 安全模式设计说明

> 本文面向开发者，说明安全模式的设计动机、架构、关键决策与已知局限。
> 代码位置：`HostApp/Runtime/Security/`、`HostApp/UI/Security/`

## 一、为什么做这个

Kinter 的定位是「有边界的能力执行平台」，但原来的模型有两个问题：

1. **默认全放行**：只要 manifest 声明了能力，网关就放行，用户没有「我不想给」的选项。
2. **没有可见性**：用户不知道一个小程序在后台调了什么。

安全模式要解决的是：**默认拒绝 + 用户现场批准 + 全程可追溯**。

## 二、设计演进（为什么不是最初的方案）

| 阶段 | 方案 | 为什么被否 |
|---|---|---|
| 1 | 幽灵权限（返回假数据） | 防不住行为检测（EXIF 一致性、连拍哈希比对），且实现成本高 |
| 2 | 纯监控（只记录不拦截） | 用户看到告警也做不了什么，不配叫「安全模式」 |
| 3 | **默认拒绝 + 一次性放行 + 分级** | 最终方案 |

## 三、核心设计：三级分级

一律全拒是最大的误判来源——地图 app 要定位、任何联网 app 要 http，全废。所以按「危害程度」分三级：

| 档位 | 能力 | 策略 |
|---|---|---|
| `critical` | contacts, health, microphone, speech, videoRecord, clipboard, clipboardImage, motion, calendar, reminder | 默认拒；**可「允许本次」，不给「以后都允许」** |
| `standard` | camera, photo, savePhoto, location, bluetooth, bluetoothScan | 默认拒；**可「允许本次」+「以后都允许」**（进信任清单） |
| `network` | http, upload, websocket, ai, openURL, share, communication, music, print | **默认放行只记录**；与隐私数据组合出现时拦下 |
| `benign` | deviceInfo, battery, vibrate, storage, files, tts, image, pdf 等 | **只记录不拦**，拦了只会让用户烦 |

分级表在 `SecurityPolicy.swift`，是能力判定的**唯一来源**。`SecurityMode` 和 `SecurityInterceptor` 都查它，不硬编码。

### 组合规则

单个能力都不敏感，组合起来可疑：

```
隐私数据能力（通讯录/健康/剪贴板/日历/提醒/语音/生物识别/账号）调用后 60 秒内出现网络外发 → 拦截并说明原因
设备读取能力（相机/相册/麦克风/录像/定位/扫码/识字等）调用后 10 秒内出现网络外发 → 同样拦下
```

用来抓「读剪贴板 → 立刻上传」这类行为。实现在 `SecurityInterceptor.evaluate` 的 `network` 分支。

## 四、拦截链路

```
小程序 JS 调 wx.chooseImage
    ↓ postMessage
BridgeMessageHandler
    ↓ （六个直通模块 router/store/auth/app/popup/permission 在这里 return，不走网关）
CapabilityGateway.invoke
    ↓ manifest.declares(module)          ← 声明校验
    ↓ disabledCapabilities               ← 用户手动禁用
    ↓ ★ SecurityInterceptor.evaluate()   ← 安全模式
         ├─ 非敏感 → allow（记录）
         ├─ network → allow（记录），除非 5s 内刚调过高危 → 拦截
         ├─ critical → 查一次性令牌；无 → denyHard
         └─ standard → 查信任清单 → 查一次性令牌 → 否则 denyGrantable
    ↓ RegionSensitiveProvider            ← 地区检查
    ↓ PermissionPolicy                   ← 系统授权检查
    ↓ ObjCExceptionCatcher               ← 异常隔离
    ↓ Provider.invoke()
```

**拦截点放在最底层（网关）**，而不是 UI 层。这样无论调用方是小程序、Agent 还是别的什么，都绕不过去。

## 五、文件职责

### 基础设施

| 文件 | 职责 | 关键实现 |
|---|---|---|
| `SecurityMode.swift` | 全局开关 | `cachedEnabled` 缓存，避免热路径每次读 UserDefaults |
| `SecurityPolicy.swift` | 三级分级表 | `tiers: [String: CapabilityTier]`，唯一判定来源 |
| `SecurityInterceptor.swift` | 拦截器 | 三级判定 + 组合规则 + 记录 + 通知 |
| `TraceRecorder.swift` | 调用记录 | JSONL 落盘，`didEnterBackground` 时 `synchronize()` |
| `SecurityEvent.swift` | 事件 + 令牌 + 通知常量 | `OneShotGrant` 消费即失效；`Notification.Name` 扩展 |
| `TrustedCapabilities.swift` | 每 app 信任清单 | `(appId, module)` 持久化到 UserDefaults |
| `SessionSeed.swift` | 会话种子 | 每次开启安全模式生成新 sessionId |

### UI

| 文件 | 职责 |
|---|---|
| `SecurityBanner.swift` | 橙色横幅，2.5s 自动收，带「允许本次 / 以后都允许」 |
| `PrivacyReportViewController.swift` | UIKit 外壳 + `UIHostingController` |
| `PrivacyReportView.swift` | SwiftUI + Swift Charts（三图） |

## 六、关键决策与取舍

### 1. 为什么用「装饰器 + 开关」而不是改 46 个 Provider

```swift
// SecurityInterceptor 只有一个入口
evaluate(module:method:appId:appName:) -> Decision
```

网关里只加一行判断，所有 Provider 零改动。以后加新能力，只要在 `SecurityPolicy.tiers` 里登记即可。

### 2. 为什么「一次性令牌」用消费制

```swift
func consume(module: String) -> Bool {
    grants.remove(key) != nil   // 删除并返回是否命中
}
```

用户点「允许本次」只放行**下一次**调用，不是本会话永久放行。这样即使 app 恶意循环调用，也每次都要用户点头。

### 3. 为什么信任清单只给 standard 档

高危能力（通讯录、健康、剪贴板）一旦泄露不可挽回，所以**永远不给永久信任**。standard 档（相机、定位）是正常 app 的核心功能，给用户「信任一次以后不烦我」的选项。

### 4. 为什么记录用 JSONL 而不是数据库

- 一行一条，追加写，不需要事务
- 会话结束时直接按 sessionId 过滤
- 用户可以在 Files app 里直接看

```
Documents/SecurityTrace/<sessionId>.jsonl
{"sessionId":"...","timestamp":"...","module":"camera","method":"chooseImage","status":"blocked","appId":"com.example"}
```

## 七、用户看到的三条通道

1. **实时横幅**：拦截瞬间从顶部滑入，**不自动收起**，等你点按钮或关掉；多个能力同时被拦会排队依次提示
2. **隐私记录页**：概览 + 能力分布 + 敏感时间轴 + 调用占比（Swift Charts）
3. **TraceRecorder**：JSONL 落盘，可导出、可重放

## 八、已知局限（必须说清楚）

这套模式**不是万能的**，以下是当前实现的缺口：

### 1. 六个直通模块绕过网关

`router / store / auth / app / popup / permission` 在 `BridgeMessageHandler` 里提前 return，**不经过 `CapabilityGateway`**。所以安全模式管不到它们——小程序照样能弹系统授权框、读宿主账号、拉起其他 app。

**修法**：把这六个模块纳入网关，或在 `SecurityInterceptor` 里加前置检查。

### 2. Agent 的 badQuery 旁路

`AgentRuntime.runCapabilityTool` 里有 `if name.hasPrefix("badQuery")` 的分流，**不走网关**，直接调 `BadQueryProvider`。安全模式完全拦不住 AI 读写沙盒外文件。

**修法**：编译期开关默认关闭 badQuery，或从 AI 提示词里移除。

### 3. 幽灵权限未实现

用户点「允许本次」拿到的是**真数据**，不是假数据。幽灵权限（基底图 + 运行时派生）只讨论了设计，没落代码。

### 4. 组合规则是时间窗，不是数据流

隐私数据 60 秒、设备读取 10 秒。恶意 app 先把数据缓存下来、过一分钟再传，规则不触发；要彻底可靠得改成会话级 taint 标记 + 行为链追踪。

### 5. WebView 导航策略（已实现）

主 frame 只允许 `file://` 与 `about:blank`，远程页面进不来；子 frame 放行 `file/https/about` 用于内嵌资源。实现在 `MiniAppWebView.webView(_:decidePolicyFor:decisionHandler:)`。

## 九、如何验证

1. 设置 → 开启安全模式
2. 打开一个小程序，触发相机/网络调用
3. 观察橙色横幅是否弹出
4. 点「允许本次」→ 这次放行，下次再拦
5. 设置 → App 隐私记录 → 看四个图表

## 十、后续优先级

| 级别 | 事项 | 成本 |
|---|---|---|
| P0 | 关掉 badQuery（编译期开关 + 删提示词用法） | 10 分钟 |
| P0 | WebView 导航白名单 | 30 分钟 |
| P1 | 六个直通模块纳入拦截 | 半天 |
| P1 | 补 ZipArchive / PackageInstaller / Gateway 单测 | 一天 |
| P2 | 幽灵权限最小闭环（只做 camera） | 一天 |

---

*本文档随代码演进，最后更新于安全模式首次提交。*
