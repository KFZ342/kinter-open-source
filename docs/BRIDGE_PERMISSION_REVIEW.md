# 桥接权限 / 相机桥接 / Web 控制横幅 深度审查报告

- 审查范围：iOS 宿主 `/Users/mawenhao/kinter-open-source` 中权限网关、相机/语音桥接、Web 控制横幅、小程序 WebView 桥接。
- 审查方式：源码走读 + 调用链追溯（原生 Runner / BridgeMessageHandler / WebAppRoutes / WebAppSession）+ `swiftc -parse` 语法检查；未跑 `xcodebuild` 全量构建（按约束留待统一构建）。
- 约束遵守：未 revert 用户工作树改动、未提交 Git、未删除用户文件、未改动 WebAccess 目录 / SettingsViewController / pbxproj / Resources/web；未新增源文件。
- 审查日期：2026-11-14。

---

## 一、结论摘要

- **authorizeWebNative 是否存在真实绕过**：存在两处缺口，已修复。
  1. 工作树中 `SecurityInterceptor`（安全模式三级判定：一次性令牌 / 信任清单 / 组合规则 / 恒定拒绝）在网关 `invoke()` 与 `authorizeWebNative()` 两条路径上的调用点均缺失，安全模式对网关调用实质失防（P0，详见 P0-1）。
  2. 两条路径均未做 `hardDenied` 恒定拒绝兜底（P0，详见 P0-2）。
- **身份伪造面**：Web 请求体里的 `appId` 由前端传入，但会话经 `AppLibrary.shared.app(id:)` 在宿主侧解析，manifest 来自已安装应用的 `manifestURL`；无法伪造成未安装应用的身份。授权令牌键已含会话 ID + appId + 能力，持久信任仅能由原生授权横幅写入，Web 侧无法写信任清单。
- **修复条数**：10 项（P0 4 项、P1 5 项、P2 记录 1 项），落地代码改动 8 个文件。
- **验证结论**：8 个改动文件 `xcrun --sdk iphonesimulator swiftc -parse` 全部通过（仅 sysroot 提示性 warning）；未做全量构建与真机/模拟器交互冒烟，残留风险见第五节。

---

## 二、P0 级问题

### P0-1 安全模式拦截器调用点在工作树中被移除，网关层失防（原生 + Web 两条路径）

**证据**

- HEAD 版本 `HostApp/Runtime/Gateway/CapabilityGateway.swift` 的 `invoke()` 在用户禁用检查之后、Provider 查找之前，调用了 `SecurityInterceptor.shared.evaluate(module:method:appId:appName:)`，`denyGrantable / denyHard` 一律返回 `permissionDenied`。
- 当前工作树中该 `switch` 已被删除；全仓库检索 `SecurityInterceptor.shared.evaluate` / `.denyGrantable` / `.denyHard`，除拦截器自身定义外**无任何调用点**（`SecurityInterceptor.swift` 成为死代码）。
- 现状 `invoke()`（`CapabilityGateway.swift:101-131`）与 `authorizeWebNative()`（`CapabilityGateway.swift:52-89`）只做：manifest 声明 → 用户禁用 → Provider/级别 → 区域 → `PermissionPolicy` 系统权限状态，不再经过安全模式判定。

**根因**

WebAccess 重构期间，网关判定被简化为只查系统权限状态；安全模式的一次性令牌（`OneShotGrant`）、信任清单（`TrustedCapabilities`）、组合规则（高危后短时外发告警）与恒定拒绝都挂在 `SecurityInterceptor.evaluate` 上，调用点移除后这些规则对网关调用全部不生效。

**攻击 / 故障路径**

- 前提：用户开启了安全模式；小程序（或经已安装应用进入的 Web 页面）在 manifest 中声明了敏感能力（如 `contacts`、`microphone`、`videoRecord`、`biometric`）。
- 路径：页面 JS → bridge `/api/bridge` 或原生 `wx.*` → 网关 `invoke/authorizeWebNative` → 不弹宿主授权横幅、不查一次性令牌与信任清单 → 直连 Provider 执行。
- 影响：安全模式“默认拒绝、每次拦高危”的设计失效；高危能力（critical）也不会被拦，仅靠系统权限状态（notDetermined 也放行）兜底。

**修复内容**

- `CapabilityGateway.swift:128-133`（`invoke()`）：恢复 `SecurityInterceptor.shared.evaluate` 判定，身份参数取宿主侧解析的 `manifest.appId / manifest.name`；`denyGrantable / denyHard` 返回 `.permissionDenied`。
- `CapabilityGateway.swift:68-73`（`authorizeWebNative()`）：接入同一套拦截器判定，Web 路径与原生路径一致，不能绕开宿主横幅里的用户同意。
- 拦截器阻塞后会通过 `.securityCapabilityBlocked` 通知宿主 `SecurityPresenter` 弹出授权横幅；用户点「允许本次」写入一次性令牌后重试即可放行，与原生流程一致。

**验证方式**

- `swiftc -parse` 通过。
- 链路走读：拦截器 → 通知 → `SecurityPresenter` → `SecurityBanner` → `OneShotGrant.grant / TrustedCapabilities.trust`，闭环与 HEAD 设计一致。
- 待统一构建后在模拟器安全模式下冒烟：声明通讯录/麦克风的小程序首次调用应被拦并出横幅，允许本次后第二次调用放行。

### P0-2 恒定拒绝能力（hardDenied）未在网关层兜底

**证据**

- `SecurityPolicy.swift:70` 定义 `hardDenied = ["badQuery"]`；拦截器原先是唯一检查点，而拦截器调用点已缺失（见 P0-1）。
- 注册表当前未注册 `badQuery`（`CapabilityRegistry.swift` 末尾注释“编译期移除”），但属于纵深防御缺口：一旦 manifest 误声明或未来误注册，网关没有第二道防线。

**根因**：恒定拒绝检查只存在于未被调用的拦截器内，网关自身不设防。

**修复内容**

- `CapabilityGateway.swift:62-64`（`authorizeWebNative`）、`CapabilityGateway.swift:122-124`（`invoke`）：在用户禁用检查之后追加 `SecurityPolicy.isHardDenied(module)` 兜底，命中即 `.permissionDenied`，不查令牌、不给授权入口。

**验证方式**：parse 通过；走读两条路径顺序：manifest 声明 → 用户禁用 → hardDenied → 拦截器 → Provider。

### P0-3 authorizeWebNative 授权链路逐项核对（身份 / 缓存 / 自动确认 / 失败默认放行）

**核对结论**

| 检查项 | 现状 | 结论 |
|---|---|---|
| 调用方身份是否前端可伪造 | `appId` 来自 Web 请求体，但 `WebAppSessionPool.sessionOrCreate(for:)` 经 `AppLibrary.shared.app(id:)` 宿主解析；未安装应用直接返回 `app_unavailable`，manifest 来自已安装应用 `manifestURL` | 不可伪造未安装身份；身份以宿主解析的 `manifest.appId` 为准 |
| 授权缓存是否按能力名全局共享 | 一次性令牌键 = `sessionId::appId::module`（`SecurityEvent.swift:35-37`），含会话与应用身份；持久信任键 = `appId + module`，且只能由原生横幅的「以后都允许」写入，Web 侧无写入口 | 无跨会话/跨应用复用；信任键不含来源维度，见 P1-5 说明 |
| 授权弹窗可否程序化自动确认 | 一次性令牌仅由 `SecurityPresenter` 在用户点横幅按钮后 `grant`；网关/桥接侧无任何程序化发放入口 | 不可自动确认 |
| 失败路径是否默认放行 | 各 guard 失败均 `return finish(.failure(...))`；`PermissionPolicy.check` 不允许 → `permissionDenied`；本次补齐 hardDenied 与拦截器失败分支 | 无默认放行 |
| 审计可追溯 | 原成功审计仅标 `webNative: true`；本次补 `source: "web"`（`CapabilityGateway.swift:44`） | 已补 |

**残留设计说明（非缺陷）**：camera/microphone 的 Web 原生采集发生在浏览器页面内（`getUserMedia` / `MediaRecorder`），设备侧系统权限状态不参与该路径判定，采集同意由浏览器自身权限弹窗给出；网关仍负责 manifest 声明、用户禁用、hardDenied、安全模式判定与审计。

**修复内容**：审计标注来源；在方法注释中固化「会话实例 + manifest.appId（宿主解析）+ 能力」三元组绑定说明（`CapabilityGateway.swift:33-35`）。

### P0-4 iOS 17+ 权限 API 正确性

**证据与修复**

- 麦克风状态：`PermissionPolicy.swift:37-48` 原仍使用已废弃的 `AVAudioSession.recordPermission`。iOS 17 起该能力迁移到 `AVAudioApplication`；已改为 `#available(iOS 17.0, *)` 分支使用 `AVAudioApplication.shared.recordPermission`，旧系统回退 `AVAudioSession`。
- `PermissionManager.swift` 现状核对（无需改）：
  - 相机 `AVCaptureDevice.requestAccess(for: .video)`，回调后台线程，经 `status(for:)` → `complete` 回到主线程（`PermissionManager.swift:501-503`）。
  - 麦克风 iOS 17 走 `AVAudioApplication.requestRecordPermission`，旧系统回退 `AVAudioSession`（`PermissionManager.swift:266-271`）。
  - 相册区分 `.readWrite` / `.addOnly`，`.limited` 状态正确映射（`PermissionManager.swift:70-83`、`276-280`）。
  - 通知 `UNUserNotificationCenter.requestAuthorization` 与状态查询齐备。
- Info.plist 用途描述核对（`HostApp/App/Info.plist`）：相机、麦克风、相册（读写/添加）、通讯录、日历（Full Access）、提醒事项（Full Access）、语音识别、健康（共享/更新）、定位（WhenInUse）、HomeKit、近距离交互、媒体资料库、运动、追踪、蓝牙、本地网络 + Bonjour 服务、NFC、Face ID 均已声明；部署目标 iOS 17.0，旧版日历/提醒事项用途描述键不再需要。
- 拒绝后引导：桥接 `permission.openSettings` 可跳转系统设置（`BridgeMessageHandler.swift:373-377`）。
- `ActivityWidget/Info.plist`：Widget 扩展内未调用任何需要用途描述的系统权限 API（已检索 `AVCapture / PHPhoto / CLLocation / EKEvent / CNContact / UNUserNotification` 均无匹配），无需补充描述，未改动。

**遗留**：`MicrophoneProvider` 直接 `record()`，未先 `AVAudioApplication.requestRecordPermission`（见第五节未修复项）。

### P0-5 相机桥接生命周期与降级

**证据与修复（本次清单内 `CameraProvider.swift`）**

- 并发竞态：原实现上一次拍照流程未结束时再次 `invoke`，新回调覆盖旧回调、picker 可能重复弹出。已加忙守卫：`completion != nil` 时返回 `providerError("camera busy")`（`CameraProvider.swift:19-22`）。
- Presenter 缺失路径：原来 `no presenter` 失败后未清空 `self.completion`，补清（`CameraProvider.swift:46`）。
- 已核对无问题项：模拟器/无相机设备 `isSourceTypeAvailable(.camera)` 降级 `unsupported`；已拒绝权限返回 `permissionDenied`；`requestAccess` 完成回调切主线程再弹 picker；delegate 回调由系统主线程派发；`presenter` 为 weak，picker 关闭后回调置空，无强引用循环。

**清单外证据（列入剩余风险，未改）**

- `QRScanProvider.swift:57-80`：自建 `AVCaptureSession` 在 `viewDidLoad` 主线程配置，`startRunning` 丢到全局队列；未使用专用 session 队列；metadata 输出 delegate 队列为主线程；`viewWillDisappear` 未统一 `stopRunning`；预览 layer 由控制器强持有。该文件不在本次授权清单内，未改动。
- `VideoRecordProvider.swift`：视频/音频权限串行请求，但无忙守卫，重复调用同样存在覆盖回调风险。

---

## 三、P1 级问题

### P1-1 WebControlBanner「踢出」按钮死点（MainAgent 交叉审查项，确认成立）

**证据**

- `WebControlBanner.swift` 原 `setup()` 中 `stack.isUserInteractionEnabled = false`，`kickButton` 虽是子视图且自身 `isUserInteractionEnabled = true`。
- UIKit 命中测试规则：父视图 `isUserInteractionEnabled == false` 时，`hitTest(_:with:)` 直接返回 `nil`，**不再下钻子视图**；子视图重新开启交互无法恢复可达性。结论：原实现下「踢出 / ×」按钮完全收不到触摸。

**修复内容**

- `WebControlBanner.swift:129`：`stack.isUserInteractionEnabled = true`，恢复子视图可达性。
- `WebControlBanner.swift:164-173`：新增 `hitTest` 覆盖——隐藏（`isVisible == false` 或 alpha ≤ 0.01）时返回 `nil` 透传底层；按钮区域优先命中 `kickButton`；其余横幅区域走默认命中，保留点按打开设置面板的手势。
- `WebControlBanner.swift:61-67`：定时刷新 Timer 改为 `Timer(timeInterval:repeats:block:)` 并加入 `RunLoop.common` mode，底层页面滚动时定时器不被暂停，活动超时隐藏仍准时。
- `WebControlBanner.swift:36-40`：重复安装（窗口重建）时先 `removeFromSuperview()`，避免横幅挂在已释放的旧窗口上。
- 可访问性：横幅改为容器视图，标题与按钮分别成为可聚焦元素，按钮补 `accessibilityLabel`（`WebControlBanner.swift:149-159`）。

**未改动 / 保持语义**：横幅可见区域为悬浮控件，保留自身点按手势；隐藏时自动透传，不遮挡底层滚动。

### P1-2 桥接消息未校验主框架、未限制消息体大小

**证据**

- `BridgeMessageHandler.userContentController` 原只校验消息名与字段存在，未校验 `message.frameInfo.isMainFrame`；内嵌子框架若能拿到 handler 引用即可向 bridge 发消息。
- 消息体无大小上限，页面塞入超大 `params` 会撑大桥接解析与 JSON 序列化成本。
- `MiniAppWebView` 回池/销毁时未摘除 script message handler；`WKUserContentController` 对 handler 是强引用，存在 controller → handler → gateway 的残留链条。

**修复内容**

- `BridgeMessageHandler.swift:33-36`：非主框架消息直接丢弃并打日志。
- `BridgeMessageHandler.swift:27,42-50`：消息体 JSON 序列化超过 256 KB 返回 `payload_too_large`，不进入网关。
- `MiniAppWebView.swift:147-150`（deinit）、`162-165`（prepareForReuse）：摘除 `bridge` 与 `jslog` 两个 handler，打破强引用循环；`resetForReuse` 原有摘除再注册逻辑保留。
- `MiniAppWebView.swift:236-238`（JSLogHandler）：同样补主框架校验。

### P1-3 PermissionManager 并发请求覆盖回调、重复弹窗

**证据**

- 定位 / 蓝牙 / HomeKit 的在飞请求由静态单变量持有单个 completion；第二个并发请求覆盖第一个，首个调用方回调永久丢失。
- 同一权限并发触发时可能重复走系统申请流程。

**修复内容**

- `PermissionManager.swift:359-385`：新增在飞注册表 `inflight: [String: [completion]]` 与 `enqueueInflight / flushInflight`：首发请求触发系统流程，后续同权限请求排队；最终状态到达后主线程统一回传全部排队回调并清空登记。
- 定位、蓝牙、生物识别、健康、本地网络、HomeKit 辅助方法改为按权限键统一 `flushInflight`；蓝牙 delegate 不再持有单个 completion，改记权限键后统一回传（`PermissionManager.swift:565-584`）。

### P1-4 TTSProvider 回调竞态、线程安全与主线程回传

**证据**

- 连续两次 `speak`：第二次直接覆盖 `self.completion`，上一次朗读的回调丢失。
- `completion` 被多线程读写，无同步；合成器 delegate 回调不保证在主线程。
- 语速参数未做边界钳制。

**修复内容**（`TTSProvider.swift`）

- `NSLock` 保护 completion 读写；新 `speak` 开始前把旧回调以 `cancelled: true` 收尾，不丢弃。
- 新增 `finish(_:)`：取走回调后置空，切主线程再通知 JS 侧；`didFinish / didCancel` 统一走该出口。
- 语速钳制到 `[AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceMaximumSpeechRate]`。

### P1-5 SecurityPolicy / TrustedCapabilities 授权判定核对

- `SecurityPolicy.tiers` 分级与注册表能力名逐项核对：除 `badQuery`（刻意恒定拒绝）外，注册表全部能力均在 `PermissionCatalog` / 分级表中有对应条目，不存在因目录名不匹配导致的静默拒绝。
- `TrustedCapabilities` 键为 `appId + module`：持久信任只能由原生安全横幅写入，Web 会话不具备写入口；当前读路径仅挂在（此前未被调用的）拦截器上，P0-1 恢复调用后即生效。信任键未区分原生/Web 来源维度，鉴于 Web 不能写信任，暂不拆键；如后续允许 Web 会话产生信任，需把来源前缀纳入键。

---

## 四、改动清单

| # | 文件 | 改动 |
|---|---|---|
| 1 | `HostApp/Runtime/Gateway/CapabilityGateway.swift` | 恢复两条路径的 `SecurityInterceptor` 判定；补 `hardDenied` 兜底；Web 审计标注 `source: "web"`；固化三元组绑定注释 |
| 2 | `HostApp/Runtime/Gateway/PermissionManager.swift` | 在飞请求并发去重与队列回传；定位/蓝牙/生物识别/健康/本地网络/HomeKit 辅助方法改造；蓝牙 delegate 改记权限键 |
| 3 | `HostApp/Runtime/Gateway/PermissionPolicy.swift` | 麦克风状态 iOS 17 改用 `AVAudioApplication.recordPermission`，废弃 API 分支回退 |
| 4 | `HostApp/Runtime/Gateway/Providers/CameraProvider.swift` | 拍照忙守卫；no-presenter 失败路径清空 completion |
| 5 | `HostApp/Runtime/Gateway/Providers/TTSProvider.swift` | 锁保护回调；并发 speak 旧回调 cancelled 收尾；delegate 回主线程；语速钳制 |
| 6 | `HostApp/UI/WebControlBanner.swift` | 修复死按钮；自定义 hitTest 透传/优先命中；Timer 入 common mode；重装剥离；VoiceOver 元素拆分 |
| 7 | `HostApp/Runtime/Render/MiniAppWebView.swift` | deinit/回池摘除 script handler；jslog 主框架校验 |
| 8 | `HostApp/Runtime/Render/BridgeMessageHandler.swift` | 主框架校验；256 KB 消息体上限与错误回包 |

未改动：`SecurityPolicy.swift`（仅核对分级表，其 5 行 logger 改动为用户工作树原有）、`TrustedCapabilities.swift`（分析后无需改键）、`ActivityWidget/Info.plist`（无需用途描述）。

---

## 五、验证结论

- 语法检查：8 个改动文件 `xcrun --sdk iphonesimulator swiftc -parse` 退出码均为 0，仅有 “sysroot for iPhoneSimulator but targeting MacOSX” 提示性 warning，无语法错误。
- 链接符号核对：`WKScriptMessage.frameInfo` 存在于 WebKit 头文件；`AVAudioApplication` 在工程原有代码中已使用；`Timer(timeInterval:repeats:block:)`、`RunLoop.main.add(_:forMode:)`、`point(inside:with:)` 均为标准 UIKit/Foundation API。
- 未执行：`xcodebuild` 全量构建、模拟器/真机交互冒烟（按约束留待统一构建）；本次结论基于源码走读与解析检查。

## 六、剩余风险

1. **安全模式闭环待真机冒烟**：拦截器恢复调用后，「拦截 → 横幅 → 允许本次/信任 → 重试放行」闭环需要在模拟器安全模式下实测；`SecurityBanner` 的按钮动作不在本次清单内。
2. **QRScannerViewController 相机会话**：主线程配置、无专用 session 队列、消失未统一停流（`QRScanProvider.swift:44-114`），文件不在本次清单，建议后续按 AVCaptureSession 专用队列重构。
3. **MicrophoneProvider 未申请麦克风权限**即 `record()`（`MicrophoneProvider.swift:24-51`），系统可能直接失败；建议启动前先走 `PermissionManager.request("microphone")`。
4. **VideoRecordProvider 无忙守卫**：重复调用存在回调覆盖风险。
5. **横幅横竖屏适配**：顶部偏移 `topInset` 仅在 `install` 时按 idiom 计算，未监听 `traitCollection` 变化；旋转后极端尺寸下位置可能需微调。
6. **临时媒体文件**：相机/相册/录音输出到 `tmp` 目录，未在会话结束后主动清理；由系统临时目录回收机制兜底。
7. **TTS 音频会话**：朗读结束后未主动 `setActive(false)` 交还其他音频；当前保留 `.duckOthers` 行为，影响可控。

## 七、未修复项及原因

| 项 | 原因 |
|---|---|
| `SecurityInterceptor` 组合规则/信任清单 UI 的端到端验证 | 需全量构建 + 模拟器安全模式冒烟，按约束未跑全量构建 |
| QRScanner / MicrophoneProvider / VideoRecordProvider 内部重构 | 文件不在本次授权清单，仅记录证据与风险 |
| `SettingsViewController` WebAccess 入口、WebAccess/*、Resources/web/*、pbxproj | 并行智能体互斥范围，未触碰 |
| 持久信任键加入来源维度 | Web 侧无信任写入口，当前无攻击面；待 Web 信任能力开放时再拆键 |
| 未新增任何源文件；未改 pbxproj | 遵守约束 |

## 八、MainAgent 交叉审查项处置

**问题**：`WebControlBanner.swift` 中 `stack.isUserInteractionEnabled = false`，`kickButton` 作为子视图自身开启交互；UIKit 命中测试在父视图禁用交互后不下钻子视图，按钮可能完全点不动。

**处置结论**：确认成立，已修复（见 P1-1）。

**判定依据**：UIView `hitTest(_:with:)` 在 `isUserInteractionEnabled == false`（或 hidden / alpha ≤ 0.01）时直接返回 `nil`，不会递归到子视图；子视图单独置 `isUserInteractionEnabled = true` 无法改变这一结果。层级为 `banner → blurView → stack(禁用交互) → kickButton`，按钮处于被禁用的中间容器之下，命中链被 stack 截断。

**修复方式**：恢复 stack 交互；新增自定义 `hitTest` 优先返回按钮，隐藏时整体透传；未为“按钮可点”做多余改动。受运行环境与约束限制（未跑全量构建、未抢占用户 Safari），未做截图级命中测试；结论依据 UIKit 命中测试规则与代码层级走读得出，建议统一构建后在模拟器点按「踢出」「×」各验证一次。
