# Kinter iOS 宿主 — 构建与启动冒烟验证报告

> 验证时间：2026-11-14（Asia/Shanghai）
> 验证范围：仅 iOS 宿主工程 `/Users/mawenhao/kinter-open-source`；独立浏览器宿主 KinterForWeb 由另一路验证。
> 本次验证目标：工程可编译通过、App 在模拟器启动不崩、WebAccess 与权限相关改动在集成层未炸掉。

## 1. 环境与 Destination

| 项 | 值 |
|---|---|
| Xcode | 16.0（Build 16A242d） |
| SDK | iPhoneSimulator 18.0 |
| 部署目标 | iOS 17.0（`IPHONEOS_DEPLOYMENT_TARGET = 17.0`） |
| Scheme / Target | `Kinter`（另有 `KinterActivityWidget` 扩展，随主 target 一起构建） |
| Destination | 已启动模拟器 `ModelerPro-iPad`，UDID `4B45E022-A012-4D82-BD70-FC6DFD7BC1F8`，iOS 18.0 |
| Bundle ID | `com.kinter.host`（扩展 `com.kinter.host.activitywidget`） |
| App 版本 | 1.2.0 (build 3) |
| 构建配置 | Debug，`CODE_SIGNING_ALLOWED=NO` |
| 构建产物 | `~/Library/Developer/Xcode/DerivedData/Kinter-ebfofvqsivbrbnaidrmyjniydiuo/Build/Products/Debug-iphonesimulator/Kinter.app` |
| 构建日志 | `/tmp/kinter-build.log`（未写入仓库） |

## 2. 构建命令与结果

### 命令

```bash
xcodebuild -project Kinter.xcodeproj -scheme Kinter \
  -destination 'id=4B45E022-A012-4D82-BD70-FC6DFD7BC1F8' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

### 结果汇总

| 轮次 | 结果 | error 数 | 说明 |
|---|---|---|---|
| 第 1 次 | 构建系统崩溃 | 1（服务级，非源码错误） | `error: unexpected service error: The Xcode build system has crashed. Build again to continue.`，发生在首次工具调用被中断之后，属构建系统残留状态，重试即恢复。 |
| 第 2 次 | 失败 | 2 | 桥接 handler 的主框架判断可选绑定类型不匹配（详见 §3）。 |
| 第 3 次 | 失败 | 3 | TTSProvider 内参数名与存储属性同名遮蔽（详见 §3）。 |
| 第 4 次（最终） | **BUILD SUCCEEDED** | **0** | 编译单元 150，warning 15（均为废弃 API / 并发建议，非阻塞）。 |

最终退出码 `0`，日志末行 `** BUILD SUCCEEDED **`。本次为增量构建（改动文件批量修复后统一重编，未反复触发全量构建）；未单独统计 clean build 时长。

## 3. 实际修复的编译错误

修复均限定在本次改动涉及文件内，做最小适配；**未使用** `git revert / checkout / stash / clean / commit / push`；**未回退**任何 P0 安全修复（SecurityInterceptor 恢复、主框架校验、同源 Origin 校验、路径 containment 均保留）。

### 3.1 硬编译错误（阻断构建，共 5 条诊断，3 个文件）

| # | 文件：行 | 诊断 | 根因 | 修复 |
|---|---|---|---|---|
| 1 | `HostApp/Runtime/Render/BridgeMessageHandler.swift:33:12` | `initializer for conditional binding must have Optional type, not 'WKFrameInfo'` | 当前 SDK 下 `WKScriptMessage.frameInfo` 为**非可选** `WKFrameInfo`，代码仍按可选类型写 `if let frame = message.frameInfo`。 | 去掉可选绑定，改为直接判断主框架：`if !message.frameInfo.isMainFrame { … return }`。主框架安全校验保留，未削弱。 |
| 2 | `HostApp/Runtime/Render/MiniAppWebView.swift:241:16` | 同上（jslog handler 内） | 同上，`if let frame = message.frameInfo` 对非可选值做绑定。 | 改为 `if !message.frameInfo.isMainFrame { return }`。 |
| 3 | `HostApp/Runtime/Gateway/Providers/TTSProvider.swift:31:13` | `cannot assign to value: 'completion' is a 'let' constant` | `invoke(method:params:completion:)` 的**参数** `completion` 与存储属性 `self.completion` 同名，参数遮蔽属性；`completion = nil` 实际在给 let 参数赋值。 | 旧回调收尾处明确引用属性：`let previous = self.completion; self.completion = nil`。 |
| 4 | `HostApp/Runtime/Gateway/Providers/TTSProvider.swift:31:26` | `'nil' cannot be assigned to type '(Result<Any, GatewayError>) -> Void'` | 同上遮蔽，参数为非可选闭包。 | 同 #3，改写 `self.completion`。 |
| 5 | `HostApp/Runtime/Gateway/Providers/TTSProvider.swift:33:21` | `cannot use optional chaining on non-optional value of type '(Result<Any, GatewayError>) -> Void'` | 同上遮蔽，`previous?` 取到的是参数而非可选属性。 | 同 #3，`previous` 取自 `self.completion`（可选），可选链恢复有效。 |

### 3.2 同源遮蔽隐患修复（可编译但逻辑失效，1 个文件）

| 文件：行 | 问题 | 修复 |
|---|---|---|
| `HostApp/Runtime/Gateway/Providers/CameraProvider.swift:19` | 并发忙闲守卫误写成参数：`guard completion == nil else`，参数 `completion` 是非可选闭包，恒不为 nil，导致「上一次拍照流程未结束」的拒绝逻辑实际不生效，picker 可能重复弹出 / 回调被覆盖。 | 改为 `guard self.completion == nil else`，守卫存储属性；分支内回调仍走参数 `completion`。 |

### 3.3 未改动项

- 其余历史告警（MetalProvider / MusicProvider / SpeechProvider / RootTabController / 若干 `contentEdgeInsets` 废弃等）未做改动，见 §6 风险清单。
- `PermissionPolicy` 对 `AVAudioApplication.recordPermission` 的引用已用 `#available(iOS 17.0, *)` 守护，部署目标 17.0，编译通过。
- `CapabilityGateway` 两处 `SecurityInterceptor.shared.evaluate(module:method:appId:appName:)` 调用签名与拦截器定义一致，编译通过。
- `LocalHTTPServer.parse` 为 `static`，调用点 `LocalHTTPServer.parse(...)` 一致。

## 4. 模拟器安装与启动冒烟

| 步骤 | 结果 |
|---|---|
| `simctl install 4B45… Kinter.app` | `INSTALL_OK`，安装成功。 |
| `simctl launch com.kinter.host` | 退出码 0，进程 PID **27191**。 |
| 启动后等待 8 秒复查 | `launchctl list` 中仍为 `27191  0  UIKitApplication:com.kinter.host…`，**进程存活**，最后退出状态 0（未崩溃）。 |
| 日志扫描（`log show --last 2m/3m`，`process == "Kinter"`） | 无 `crash / fatal / exception / terminat / signal / abort / dyld / unresolved symbol / EXC_` 等关键字。 |
| WebAccess 服务 | 启动后本地监听 `127.0.0.1:18765`（lo0），持续收到 127.0.0.1 入站连接并打 `[WebAccess] 收到连接 …` 日志；本地 HTTP 服务与桥接链路在集成层正常拉起，未出现启动即崩。 |

说明：App 是否停在登录/首页未做 UI 级断言；按判定标准，**允许因缺少登录态停在某页面，不接受启动即崩**——本次未观测到崩溃。

## 5. pbxproj 文件登记核对表

已先备份：`cp Kinter.xcodeproj/project.pbxproj /tmp/pbxproj.bak`。核对结论：**主 target 本次改动涉及的 Swift 与顶层 web 资源均已登记，无需补录；`project.pbxproj` 本次未被修改**（`diff` 与备份一致）。

### 5.1 Swift 文件（Kinter target Sources）

| 文件 | PBXBuildFile | PBXFileReference | Group | Sources 阶段 | 结论 |
|---|:---:|:---:|:---:|:---:|---|
| `HostApp/Runtime/WebAccess/LocalHTTPServer.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |
| `HostApp/Runtime/WebAccess/WebAccessService.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |
| `HostApp/Runtime/WebAccess/WebAccessSettings.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |
| `HostApp/Runtime/WebAccess/WebAppAssets.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |
| `HostApp/Runtime/WebAccess/WebAppRoutes.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |
| `HostApp/Runtime/WebAccess/WebAppSession.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |
| `HostApp/UI/WebControlBanner.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |
| `HostApp/UI/Settings/WebAccessViewController.swift` | ✓ | ✓ | ✓ | ✓ | 已登记 |

### 5.2 顶层 web 资源（Kinter target Resources）

| 文件 | Resources 阶段 | 结论 |
|---|:---:|---|
| `console.css` | ✓ | 已登记 |
| `console.js` | ✓ | 已登记 |
| `kinter-console.html` | ✓ | 已登记 |
| `manifest.webmanifest` | ✓ | 已登记 |
| `pwa-180.png` | ✓ | 已登记 |
| `pwa-192.png` | ✓ | 已登记 |
| `pwa-512.png` | ✓ | 已登记 |
| `runner.html` | ✓ | 已登记 |
| `sw.js` | ✓ | 已登记 |
| `web-bridge.js` | ✓ | 已登记 |

> 资源在 bundle 中被平铺到根目录（无 `web/` 子目录），代码侧 `bundledData/bundledText` 已同时兼容「子目录」与「平铺根目录」两种查找路径，运行时可命中。

### 5.3 未登记目录（记录，未补）

- `HostApp/Resources/web/kinter-for-web/` 下现有 7 个文件（`index.html`、`app.css`、`bridge.js`、`icon.png`、`ktml.js`、`wx.js`、`zip.js`）**均未登记**进 pbxproj，产物 bundle 中也不存在该目录 / `zip.js`。
- 当前 Swift 代码未从 bundle 读取该目录（WebAppAssets 只服务已安装应用目录 + SDK 脚本），因此**不阻塞本次编译与启动**。
- 已知问题：该目录缺 `app.js`（`index.html` 引用但文件不存在）。按 `docs/WEB_ACCESS.md` 约定，该副本由独立工程（`KinterForWeb`）整体同步，**不在本仓库手补**；待同步后再评估是否把整目录登记进 Resources。本次按要求未补文件、未改 pbxproj。

## 6. 阻塞项与剩余风险

### 6.1 阻塞项

无。工程编译通过，App 在模拟器正常启动并存活，WebAccess 本地服务已拉起监听。

### 6.2 剩余风险（非阻塞，供后续跟进）

1. **Swift 6 并发告警（LocalHTTPServer）**
   - `LocalHTTPServer.swift:384` 捕获变量 `responded` 在并发代码中被修改；`:385` 捕获变量 `bodyItem` 被并发引用。当前 Swift 5 模式仅告警，Swift 6 语言模式下会升级为错误。建议后续用锁 / 局部不可变状态重构。
2. **废弃 API 告警**
   - `PermissionPolicy.swift:57/60` `authorized` 自 iOS 17.0 废弃（建议区分 full access / write-only）；
   - `SpeechProvider.swift:26` `requestRecordPermission` 自 iOS 17.0 废弃（建议 `AVAudioApplication` 接口）；
   - `PermissionManager.swift:214` `isSupported` 自 iOS 16.0 废弃；
   - 多处 `UIButton.contentEdgeInsets` 在 UIButtonConfiguration 下被忽略（WebControlBanner:111 等）。
3. **WebControlBanner 定时器生命周期**
   - 单例横幅持有一个 `repeating` Timer 加入 `.common` 模式；`install(in:)` 重复安装前会 invalidate 旧定时器，但无 `deinit` 兜底。单例生命周期等同 App 进程，泄漏边界可控；若后续支持横幅主动销毁，需补定时器摘除。
4. **历史崩溃记录（非本次复现）**
   - `~/Library/Logs/DiagnosticReports/Kinter-2026-11-13-191256.ips` 为 11 月 13 日 19:12 的旧崩溃（版本 1.2.0 build 3，macOS 15.7.8 模拟器），早于本次改动；本次启动后未产生新的 Kinter `.ips`。建议后续单独复盘该旧崩溃堆栈。
5. **未覆盖的验证面**
   - 本次未跑 UI 测试 / XCUITest；未对 WebAccess 的鉴权、CORS、路径穿越、请求大小、令牌注销轮换、相机/相册桥接做接口级手工或自动用例（这些见 `WEB_ACCESS_SECURITY_REVIEW.md`、`BRIDGE_PERMISSION_REVIEW.md`）。
   - 未在真机验证；仅 iOS 18.0 模拟器。
6. **kinter-for-web 副本缺口**
   - 缺 `app.js`，且现有 7 文件未进 bundle；经本地 HTTP 服务打开该控制台时对应脚本会 404。待独立工程整体同步后再登记。

## 7. 约束遵守说明

- 未执行任何 `git checkout / revert / stash / clean / commit / push`；工作树原有 13 个修改 + 未跟踪路径保持原样。
- 未向仓库内写入 build 目录；产物在 DerivedData，日志在 `/tmp`。
- 未改动或清空任何真实 LocalStorage / 用户数据；本次仅在模拟器安装 Debug 包并启动。
- 安全加固成果（SecurityInterceptor 恢复、主框架 / 同源校验、路径 containment）在修复中全部保留，未为编过而删除。
