# Kinter iOS WebAccess 本地 HTTP 服务安全审查报告

- 审查对象：`/Users/mawenhao/kinter-open-source` 本地 WebAccess HTTP 服务子系统
- 审查范围：`HostApp/Runtime/WebAccess/*`、`HostApp/UI/Settings/WebAccessViewController.swift`、`HostApp/App/SceneDelegate.swift`（仅生命周期）、`docs/WEB_ACCESS.md`（仅追加）
- 审查方式：逐文件代码走查 + 纯逻辑独立脚本验证 + `swiftc -parse` 语法级校验；未跑 `xcodebuild` 全量构建（按约束由后续统一构建验证）
- 结论：发现并落地修复 **12** 项（P0 7 项、P1 5 项），记录残留风险与范围外事项 **10** 项；未改动用户数据、未提交 Git、未 revert 用户在途改动。

---

## 一、P0（高危，已修复）

### P0-1 CORS 使用通配 `Access-Control-Allow-Origin: *`，跨源可读带令牌响应

- **证据**：修复前 `LocalHTTPServer.swift` `WebHTTP.cors` 对所有响应（含鉴权后接口）下发 `ACAO: *`、`Allow-Methods`、`Allow-Headers`。
- **根因**：通配源意味着任意网页只要拿到令牌（或通过其它渠道泄漏）即可跨站读取接口响应；CORS 被当成了安全边界，而令牌才是硬门槛。
- **修复**：
  - 移除通配 ACAO；新增同源判定 `WebHTTP.isSameOrigin(_:)` 与 `WebHTTP.hostOrigin(of:)`（`LocalHTTPServer.swift:126-136`）。
  - 仅当请求 `Origin` 与 `Host` 同源时回显该 Origin 并带 `Vary: Origin`（`WebHTTP.withOrigin`，`LocalHTTPServer.swift:139-147`）；跨源不带 ACAO。
  - 鉴权响应统一走 `WebHTTP.authorized(_:for:)`（`LocalHTTPServer.swift:160-162`），在 `WebAccessService.finish` 与 `/api/invoke` 回包处接入。
  - OPTIONS 预检只放行同源，跨源预检 403（`WebAccessService.swift:311-322`）。
- **验证**：独立脚本 Origin 同源/跨源/无 Origin/Host 缺失 4 条用例全部 PASS；`swiftc -parse` 通过。

### P0-2 缺少 Origin/CSRF 校验，任意网页可向 127.0.0.1 发起状态变更请求

- **证据**：修复前 `WebAccessService.handle` 仅校验令牌，不校验 `Origin`/`Referer`；Cookie 虽为 `SameSite=Strict`，但查询串令牌与自定义头通道没有跨源拦截兜底。
- **根因**：本地服务不能假设"能访问 127.0.0.1 的都是可信方"——本机浏览器里任意网页都能向回环/局域网端口发请求；状态变更接口（导入/卸载/改设置/踢出/轮换令牌）需要跨源校验作为第二道防线。
- **修复**：鉴权通过后增加同源守卫，Origin 存在且与 Host 不一致 → 403 `cross_origin`；无 Origin 头（同源导航、命令行、本地脚本）不拦截，仍由令牌把关（`WebAccessService.swift:402-408`）。
- **验证**：脚本 Origin 用例 PASS；同源控制台页面与接口同源，不受影响。

### P0-3 应用图标路径未做目录 containment，恶意 manifest 的 `icon` 字段可越界读文件

- **证据**：修复前 `WebAppAssets.iconResponse` 对 `app.iconFileName` 与 manifest `icon` 直接 `app.directory.appendingPathComponent(...)` 后 `Data(contentsOf:)`，无 standardize、无根目录前缀校验、未解析符号链接（MainAgent 交叉审查项 1）。
- **根因**：`icon` 来自安装包 manifest，属不可信输入；`../../..`、绝对路径形态、目录内符号链接都可能把文件读到应用目录之外。
- **修复**：新增统一路径校验 `WebAppAssets.safeURL(app:relative:)`（`WebAppAssets.swift:19-42`）：百分号解码一次 → 拒绝绝对路径 / `file://` / NUL / `..` 段 / 中间空段 → standardize → `resolvingSymlinksInPath()` 解析真实路径 → 根目录前缀包含二次校验。`iconResponse` 的自定义图标与 manifest 图标两条路径均改走 `safeURL`，并拒绝目录（`WebAppAssets.swift:192-215`）。
- **验证**：独立脚本对 `../secret.txt`、`%2e%2e%2fsecret.txt`、`/etc/passwd`、`sub/../../secret`、目录内符号链接逃逸、NUL 字节共 6 条越界用例全部拒绝（PASS）。

### P0-4 页面/静态资源路径校验可被符号链接与编码绕过

- **证据**：修复前 `resolvePage` 仅做 `contains("..")` 子串判断 + `standardizedFileURL`，`assetResponse` 同样未解析符号链接；`standardizedFileURL` 只清理词法路径，不解析符号链接。
- **根因**：子串 `..` 判断漏掉编码形式与符号链接逃逸；词法标准化后真实落点仍可能在根目录之外。
- **修复**：`resolvePage`（`WebAppAssets.swift:45-77`）与 `assetResponse`（`WebAppAssets.swift:174-189`）统一改走 `safeURL`，并在解析真实路径后再做一次前缀校验；静态资源额外拒绝目录实体。
- **验证**：脚本符号链接逃逸用例 PASS；正常页面 `index.html`、子目录 `sub/detail.ktml` 放行 PASS。

### P0-5 请求报文缺少长度/方法/编码校验，存在内存放大、走私与连接吊死风险

- **证据**：修复前 `LocalHTTPServer.parse` 对请求行/头数量/头总长度无上限；`Content-Length` 用 `Int(...) ?? 0` 兜底，负数、非数字、超大值、重复且不一致的 CL、`Transfer-Encoding: chunked` 均未显式拒绝；方法未做白名单（MainAgent 交叉审查项 2）。
- **根因**：无限累积头区可撑爆内存；非法 CL 导致长度判定错误，存在请求走私空间；非白名单方法进入路由后落到 404，语义不严谨。
- **修复**（`LocalHTTPServer.swift`）：
  - 上限：请求行 8 KB、头区 64 KB、头字段 64 个（`207-211`）；超限回 413 并断开。
  - 方法白名单 `GET/POST/HEAD/OPTIONS`，其余 405（`123`、`434-437`）。
  - 拒绝 `Transfer-Encoding`（chunked）；重复且取值不一致的 CL 拒绝；CL 必须为非负纯数字且 ≤ 40 MB，否则 400/413（`456-478`）。
  - 非法 UTF-8 请求头、请求行/路径中的 NUL 字节拒绝 400。
  - 解析结果改为 `ParseOutcome`（`.request/.needMore/.reject`），拒绝路径主动回错误并关闭连接（`403-411`）。
- **验证**：脚本 CL 合法/负数非数字/超大值/chunked 4 条用例 PASS；`swiftc -parse` 通过。

### P0-6 慢速请求体可永久占住连接（header 解析后 body 无超时）

- **证据**：修复前首包超时 `idleItem` 在请求头解析完成后即被取消；此后 body 被慢速 trickle 灌入时不再有任何读超时，连接长期占位。
- **根因**：缺少 body 读取阶段的独立 deadline，慢速攻击可耗尽连接/文件描述符。
- **修复**：新增 `bodyDeadline = 15s`；头区到齐而 body 未到齐时挂 body 超时项，超时未完成即关闭连接（`LocalHTTPServer.swift:197`、`338-339`、`364-370`）。保留原首包 25s、业务响应 40s、长任务 180s 三档超时。
- **验证**：代码走查确认三档超时 + body 超时覆盖连接全生命周期；脚本 CL 校验 PASS。

### P0-7 并发连接无上限，可被占满 fd / 内存

- **证据**：修复前 `accept` 对每条连接直接 `start`，没有活跃连接计数与上限。
- **根因**：本地服务暴露在局域网/回环下，无并发上限时可被大量半开或慢速连接耗尽资源。
- **修复**：新增 `activeConnections` 计数（NSLock 保护），上限 32；超限直接回 503 `too_many_connections` 并断开；所有终止路径（错误、对端关闭、发送完成、超时）统一走 `close()` 释放计数（`LocalHTTPServer.swift:213-216`、`304-333`、`394-398`）。
- **验证**：代码走查计数在所有退出路径释放；`swiftc -parse` 通过。

---

## 二、P1（中危，已修复）

### P1-1 关闭服务不轮换令牌，旧链接 / 旧 Cookie 继续有效

- **证据**：修复前 `stop()` 只断开 listener，令牌保留在 Keychain/UserDefaults；旧浏览器携带旧 Cookie 或旧 `?token=` 在服务重启后仍可通过鉴权。
- **根因**：关闭/断开不是真正的吊销；令牌生命周期与服务生命周期脱节。
- **修复**：`stop()` 改为 `stop(revokeToken: true)`：轮换令牌、清空 Web 小程序会话池、清空活动与在线状态（`WebAccessService.swift:129-152`）。换端口重启走 `stop(revokeToken: false)`，保留当前令牌避免当前浏览器被无故踢下线（`225-231`）。
- **验证**：代码走查；令牌常量时间比较逻辑脚本 PASS。

### P1-2 App 进后台后本地服务仍挂着监听窗口

- **证据**：修复前无前后台生命周期钩子，App 切后台后 listener 继续存活（iOS 后台套接字多数被挂起，但监听窗口与令牌仍在）。
- **根因**：后台场景不需要对外提供 Web 控制台，应缩小暴露面。
- **修复**：`WebAccessService.init` 注册 `didEnterBackground` / `willEnterForeground` 通知；进后台即 `stop()`（吊销令牌），回前台按 `autoStart` 偏好自动恢复（`WebAccessService.swift:47-68`）。
- **验证**：`swiftc -parse` 通过；行为变化已写入 `docs/WEB_ACCESS.md` 末尾。

### P1-3 缺少点击劫持 / 引用泄露 / MIME 嗅探等安全响应头

- **证据**：修复前仅 `X-Content-Type-Options: nosniff`；无 `X-Frame-Options`、`Referrer-Policy`、CSP 帧约束。
- **根因**：控制台页面可被任意页面 iframe 嵌入（点击劫持）；令牌走查询串时可能经 Referer 泄漏；响应缺少帧策略约束。
- **修复**：`WebHTTP.cors` 统一补 `X-Frame-Options: DENY`、`Referrer-Policy: no-referrer`、`Content-Security-Policy: frame-ancestors 'none'; base-uri 'self'`，并保留 `nosniff` 与默认 `Cache-Control: no-store`（`LocalHTTPServer.swift:149-157`）。
- **验证**：代码走查所有响应经 `cors`/`authorized` 包装。

### P1-4 探活接口泄露端口与应用标识

- **证据**：修复前 `GET /healthz` 返回 `app`、`port` 等内部信息，且该接口免鉴权。
- **根因**：免鉴权端点不应披露内部拓扑信息。
- **修复**：`/healthz` 仅返回 `{"ok": true}`（`WebAccessService.swift:326-328`）。
- **验证**：代码走查。

### P1-5 资源副本缺 `app.js`，经服务访问必然 404（记录项，按约束不补副本）

- **证据**：`HostApp/Resources/web/kinter-for-web/index.html:187` 引用 `app.js`，该目录副本中无此文件（现有 index.html / app.css / bridge.js / icon.png / ktml.js / wx.js / zip.js）；独立副本 `/Users/mawenhao/Doubao/chats/2026-11-13/new-chat/KinterForWeb` 中存在 `app.js`。
- **根因**：两处副本未同步。
- **处置**：按约束**未修改该副本目录**；已在 `docs/WEB_ACCESS.md` 末尾「资源同步与已知问题」一节写明同步源、文件清单与目标目录，由统一同步流程补齐。
- **验证**：`ls` 两侧目录核对一致。

---

## 三、P2（低危 / 记录项，本次未改代码）

| 编号 | 事项 | 证据 | 处置与原因 |
|---|---|---|---|
| P2-1 | 令牌仍支持查询串 `?token=` 传递，可能出现在 URL 历史 / Referer / 日志 | `WebAccessService.swift:481`、`accessURL` | 保留：扫码/开机引导需要 URL 带令牌；已靠 `Referrer-Policy: no-referrer`、SameSite=Strict、可随时轮换缓解。后续可改为一次性换 Cookie 的 bootstrap 流程。 |
| P2-2 | Web 会话池按 appId 缓存，无空闲过期；多客户端共享同一令牌 | `WebAppSession.swift:40-77` | 记录：单令牌模型下多端隔离属产品设计；后续可加会话 TTL 与按客户端签发。 |
| P2-3 | `/api/meta` 鉴权后回传 `localIP`、账号登录态等信息 | `WebAccessService.swift:532`、`483-487` | 记录：均在鉴权后通道内；控制台信息面板需要这些数据。 |
| P2-4 | 设置回包携带当前令牌明文 | `WebAppRoutes.swift:462` | 记录：鉴权后通道，设置页需要展示/复制令牌；与既有产品行为一致。 |
| P2-5 | 未实现 Range 请求与 304 协商缓存 | 全文件 | 记录：单请求单连接 `Connection: close` 模型，静态资源带短缓存头；影响低，后续按需补。 |
| P2-6 | 商店源 URL 由 Web 端提交，服务端拉取存在 SSRF 面 | `WebAppRoutes.swift:576` → `StoreManager.addSource` | **范围外**：`StoreManager` 不在本次文件清单；转对应模块复核内网/私网地址拦截。 |
| P2-7 | ZIP 导入/预览的 zip-slip、压缩炸弹风险在解压器内 | `WebAppRoutes.swift:230`、`271` → `PackageInspector/PackageInstaller` | **范围外**：解包组件不在本次清单；转安装器模块复核路径净化与解压限额。 |
| P2-8 | `authorizeWebNative` 授权判定实现需复核是否可绕过 | `WebAppRoutes.swift:417-430` → `session.gateway.authorizeWebNative` | **范围外**：`CapabilityGateway` 不在本次清单；转网关模块复核相机/麦克风 Web 原生授权链路。 |
| P2-9 | 部分错误回包携带 `error.localizedDescription`，可能含内部路径 | `WebAppRoutes.swift:252`、`289`、`579`、`623` | 记录：消息来自安装器/商店管理器；后续可对 4xx/5xx 回包做通用文案 + 内部日志分离。 |
| P2-10 | `WebAccessViewController.onStateChange` 未在 deinit 显式置空 | `WebAccessViewController.swift:37-39` | 记录：闭包为 `[weak self]`，服务为单例，无实际泄漏；可后续补 `deinit` 置空。 |

---

## 四、MainAgent 交叉审查项处置

### 项 1：`iconResponse` 路径穿越（P1 → 本次按 P0 处置）

- **采纳**：是。
- **证据**：修复前 `WebAppAssets.iconResponse` 直接 `app.directory.appendingPathComponent(manifest icon)`，无 standardize / 根目录 containment / 符号链接解析。
- **改动内容**：新增 `safeURL` 统一校验（百分号解码 → 拒绝绝对路径/NUL/`..`/空段 → standardize → 符号链接真实路径解析 → 前缀包含校验）；`iconResponse` 两条图标路径接入；复核同文件 `resolvePage`、`assetResponse` 存在同类缺口，一并加固。
- **验证结果**：独立脚本 6 条越界用例（`..`、编码 `%2e%2e`、绝对路径、多级 `..`、符号链接逃逸、NUL）全部拒绝；2 条正常路径放行。

### 项 2：`parse` 负数/超大 CL、超长 header/request line 无显式拒绝（P2 → 本次按 P0 处置）

- **采纳**：是。
- **证据**：修复前 `parse` 仅 `Int(headers["content-length"] ?? "0") ?? 0`，无 header 数量/总长度/请求行上限，无 CL 合法性与重复校验。
- **改动内容**：请求行 8 KB / 头区 64 KB / 头字段 64 个上限；CL 必须非负纯数字且 ≤ 40 MB；拒绝 chunked、重复且不一致 CL；非法请求回 400/405/413 并主动关闭；补 body 读取 15s 超时。慢速读超时复核：原有首包 25s，本次补齐 body 阶段超时，业务响应超时维持 40s / 长任务 180s。
- **验证结果**：脚本 CL/chunked 4 条用例 PASS；`swiftc -parse` 7 个文件退出码 0。

---

## 五、改动清单

| 文件 | 改动性质 | 主要内容 |
|---|---|---|
| `HostApp/Runtime/WebAccess/LocalHTTPServer.swift` | 加固（约 +130 行） | 同源判定与安全头枚举；并发计数与上限；body 超时；报文上限；方法白名单；CL/chunked/重复 CL 校验；`ParseOutcome` 拒绝路径；关闭 P2P 通道 |
| `HostApp/Runtime/WebAccess/WebAccessService.swift` | 加固（约 +50 行） | 前后台生命周期观察者；`stop(revokeToken:)` 令牌吊销；同源/CSRF 守卫；`authorized` 统一包装；healthz 精简；invoke 回包接入同源 Origin |
| `HostApp/Runtime/WebAccess/WebAppAssets.swift` | 加固（约 +42 行） | `safeURL` 统一路径 containment；页面/静态资源/图标三路接入；目录拒绝；符号链接真实路径二次校验 |
| `HostApp/Runtime/WebAccess/WebAppRoutes.swift` | 未改代码 | 仅走查；SSRF / zip-slip / 授权判定列入范围外残留项 |
| `HostApp/Runtime/WebAccess/WebAppSession.swift` | 未改代码 | 会话过期/多端隔离列入 P2-2 |
| `HostApp/Runtime/WebAccess/WebAccessSettings.swift` | 未改代码 | 复核：24 字节 SecRandom 令牌（192 bit）、常量时间比较，符合要求 |
| `HostApp/UI/Settings/WebAccessViewController.swift` | 未改代码 | 弱引用回调，无实际泄漏（P2-10） |
| `HostApp/App/SceneDelegate.swift` | 未改代码 | 生命周期收口在 Service 内部观察者；原有 autoStart 逻辑保留 |
| `docs/WEB_ACCESS.md` | 末尾追加 | 「资源同步与已知问题」+ 本次行为变化说明，未重写已有内容 |
| `Kinter.xcodeproj/project.pbxproj` | 未动 | 未新增文件、未新增依赖 |

---

## 六、验证结论

1. **语法级校验**：`xcrun --sdk iphonesimulator swiftc -parse` 对 7 个 Swift 文件解析通过，退出码 0（仅有 sysroot 警告，与代码无关）。
2. **纯逻辑独立验证**：临时脚本 `verify/security_logic_check.swift` 共 19 条用例，全部 PASS：
   - 路径 containment 8 条（正常放行 2，越界拒绝 6）；
   - 令牌常量比较 3 条；
   - Origin 同源判定 4 条；
   - Content-Length / chunked 校验 4 条。
3. **未执行项**：按约束未跑 `xcodebuild` 全量构建、未启动模拟器 UI 冒烟；类型完整性与运行时行为待统一构建环节复核。
4. **数据安全**：未读写/删除任何用户真实数据；测试文件均在系统临时目录，脚本结束自动清理；未执行 `git commit` / `git checkout` / revert。

### 手工复现命令序列（服务在本机启动后，端口以实际为准 8765）

```bash
# 1. 未带令牌 → 401
curl -i http://127.0.0.1:8765/api/meta

# 2. 带错误令牌 → 401（常量时间比较）
curl -i -H "X-Kinter-Token: wrong" http://127.0.0.1:8765/api/meta

# 3. 跨源 Origin → 403（同源浏览器控制台不受影响）
curl -i -H "Origin: http://evil.example" http://127.0.0.1:8765/api/meta

# 4. chunked 请求 → 400
curl -i -H "Transfer-Encoding: chunked" -H "Content-Length: 5" -d "hello" http://127.0.0.1:8765/api/meta

# 5. 超大 body → 413
curl -i -H "Content-Length: 99999999" http://127.0.0.1:8765/api/meta

# 6. 路径穿越资源 → 403/404（appId 替换为已安装应用）
curl -i "http://127.0.0.1:8765/apps/<appId>/../../secret.txt"
curl -i "http://127.0.0.1:8765/apps/<appId>/%2e%2e%2fsecret.txt"

# 7. 非白名单方法 → 405
curl -i -X TRACE http://127.0.0.1:8765/

# 8. 安全响应头（同源 GET 外壳页面）
curl -i http://127.0.0.1:8765/ | grep -iE "x-frame-options|referrer-policy|x-content-type-options|content-security-policy"
```

---

## 七、剩余风险

- **监听面**：服务按产品设计监听局域网 Wi-Fi（扫码从其它设备打开控制台），NWListener 默认通配绑定 IPv4/IPv6；本次已关闭 AWDL/临机互联（`includePeerToPeer = false`），确认未注册 Bonjour/mDNS。暴露面由令牌 + SameSite Cookie + 同源校验 + 安全头共同兜底；如需进一步收敛，后续可增加「仅回环访问」开关。
- **范围外组件**：商店源 SSRF（StoreManager）、ZIP 解包 zip-slip/炸弹（PackageInspector/Installer）、Web 原生相机/麦克风授权判定（CapabilityGateway）需对应模块单独复核。
- **构建与运行时**：本次仅语法级校验，类型检查、链接、模拟器实跑待统一构建环节确认；后台/前台切换、换端口重启、长轮询断开重连建议在冒烟中各走一遍。
- **副本同步**：`kinter-for-web` 缺 `app.js`，统一同步前经服务打开的该控制台交互脚本 404。

## 八、未修复项及原因

| 事项 | 未修复原因 |
|---|---|
| 仅回环绑定（127.0.0.1） | 产品功能要求扫码从同 Wi-Fi 其它设备访问，改为回环-only 会破坏既有用法；记录为剩余风险，建议后续加开关。 |
| StoreManager 源 URL SSRF 过滤 | 文件在本次范围外，避免并行修改冲突；已列 P2-6 转对应模块。 |
| ZIP 解包安全（路径净化/解压限额） | 解压器在 Core/Package，范围外；已列 P2-7 转安装器模块。 |
| `authorizeWebNative` 授权链路复核 | 实现在 CapabilityGateway，范围外；已列 P2-8 转网关模块。 |
| Range / 304 协商缓存 | 单连接 close 模型下影响低，列为后续优化（P2-5）。 |
| 会话 TTL / 多客户端令牌隔离 | 属产品模型调整，需产品确认后再改（P2-2）。 |
