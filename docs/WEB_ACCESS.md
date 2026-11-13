# Web 端访问（Web Access）

在设备上起一个本地 HTTP 服务，浏览器访问它就能得到一个**和 App 1:1 对齐的 Web 控制台**：
导入/安装小程序 ZIP、直接运行小程序（页面 + `wx.*` 能力回到设备上的能力网关）、查看 Kinter 信息、修改偏好设置。

```
浏览器（电脑 / 同局域网设备）
        │  http://<设备IP>:8765
        ▼
LocalHTTPServer（NWListener，设备内）
        ├── /                 控制台 SPA（导入 / 应用库 / 商店 / 设置）
        ├── /run             小程序运行器（导航栏 + iframe）
        ├── /apps/<id>/<p>   小程序页面（.html 直出 / .ktml 走 KTMLCompiler）与静态资源
        ├── /sdk/wx.js        官方 SDK
        ├── /sdk/ktml.js      KTML 运行时
        ├── /web-bridge.js   浏览器版桥接（替代 WKWebView messageHandler）
        └── /api/*           宿主能力：应用库、导入、运行、设置、商店、能力网关
                                 │
                                 ▼
                     CapabilityGateway（manifest 声明 → 禁用能力 → 安全模式 → 系统权限）
```

## 为什么能 1:1

- **页面渲染同源**：`WebAppAssets.renderDocument` 复用 `PageRouter` 的解析规则（裸路径先 `.html` 后 `.ktml`），
  `.ktml` 走同一个 `KTMLCompiler`，产物与 App 内完全一致。
- **脚本注入时机等价**：原生用 `WKUserContentController` 在 documentStart 注入 `wx.js` / `ktml.js`；
  浏览器没有这个机制，服务端在返回页面时把 `<script>` 插到 `<head>` 之后，早于页面自身脚本执行。
- **桥接协议一致**：`/web-bridge.js` 复刻 `window.webkit.messageHandlers.bridge.postMessage`、
  `window.__wxBridgeCallback`、`window.__wxEmitBatch` 三个入口，`SDK/wx.js` 一行都不用改。
- **网关链路一致**：Web 会话 `appId = kinter.webaccess`（名称「Web 端访问」），
  manifest 声明除 L3 与 hard-denied 外的全部已注册能力，走和 App 内相同的
  manifest 声明校验 → 用户禁用能力 → `SecurityInterceptor` → `PermissionPolicy`。

## 路由

| 路径 | 说明 | 鉴权 |
| --- | --- | --- |
| `GET /` | Web 控制台（SPA，四个 Tab） | 可选（带 `?token=` 会种 cookie） |
| `GET /console.css`、`GET /console.js`、`GET /web-bridge.js` | 控制台静态资源 | 否 |
| `GET /healthz` | 探活 | 否 |
| `GET /run?appId=&page=&name=` | 小程序运行器外壳 | 是 |
| `GET /apps/<appId>/<path>` | 小程序页面与资源（含注入） | 是 |
| `GET /sdk/wx.js`、`GET /sdk/ktml.js` | SDK 与 KTML 运行时 | 是 |
| `GET /api/meta` | 版本 / 设备 / 系统 / 账号 / 能力数 / 局域网 IP | 是 |
| `GET /api/apps` | 应用库（含能力、入口页、图标、运行地址） | 是 |
| `POST /api/apps/preview` | 上传 ZIP 预览（原始 body），返回 manifest 与能力分级 | 是 |
| `POST /api/apps/import?filename=&category=&overwrite=1` | 安装 ZIP（原始 body） | 是 |
| `POST /api/apps/update` | 改分类 / 能力开关 | 是 |
| `POST /api/apps/delete` | 卸载应用 | 是 |
| `GET /api/apps/<appId>/icon` | 应用图标（没有就生成首字占位 PNG） | 是 |
| `POST /api/bridge` | 小程序 `wx.*` 调用入口 | 是 |
| `GET/POST /api/settings` | 读写偏好设置 | 是 |
| `GET /api/store` | 商店源与聚合条目 | 是 |
| `POST /api/store/source`、`/api/store/source/remove` | 增删应用源 | 是 |
| `POST /api/store/refresh` | 刷新所有源 | 是 |
| `POST /api/store/install` | 下载并安装商店条目 | 是 |
| `GET /api/audit?limit=` | 能力审计日志 | 是 |
| `GET /api/poll?since=&wait=&appId=` | 事件长轮询（websocket / 共享值 / 网络变化） | 是 |
| `POST /api/invoke` | 直接调用能力（脚本/调试用） | 是 |

## 鉴权

四种写法任一即可：

- `X-Kinter-Token: <token>`
- `Authorization: Bearer <token>`
- `?token=<token>`
- `Cookie: kinter_web=<token>`

因为 iframe 里的页面请求带不了自定义头，控制台只要用前三种方式鉴权成功一次，服务端就会补
`Set-Cookie: kinter_web=<token>; Path=/; HttpOnly; SameSite=Strict; Max-Age=604800`，
之后 `/run`、`/apps/**`、`/sdk/**` 这些页面请求自动通过。

令牌 24 字节随机（`SecRandomCopyBytes`），优先存 Keychain，取不到时降级到 UserDefaults；
比较用常量时间实现，避免计时侧信道。

## 安全边界

- 默认只听局域网，且只在 App 运行期间监听；`autoStart` 打开时随 App 启动。
- 所有能力调用都要过网关：manifest 未声明、用户已禁用、安全模式拦截、系统未授权，四道关卡与原生一致。
- Web 会话不声明 L3 能力，hard-denied 能力也不会出现在声明表里。
- 页面资源做 `..` 穿越防护，只允许读取应用包目录内的文件。
- 审计日志照常记录到 App 的隐私记录里。

## 使用

1. App →「设置 → 互联 → Web 端访问」，打开开关（默认端口 8765，可改）。
2. 电脑与设备连同一 Wi-Fi，浏览器打开页面上的地址，或直接扫二维码（二维码里带了 `?token=`，打开即登录）。
3. 控制台里：
   - **导入应用**：选择或拖入 ZIP → 预览 manifest 与能力分级 → 选分类 → 安装。
   - **应用库**：搜索、按分类浏览、打开运行、改分类/能力开关、卸载。
   - **商店**：添加 `index.json` 源、刷新、安装、打开。
   - **设置**：Kinter 信息（版本/设备/系统/账号/能力数）、安全模式、启动方式、安装确认、
     风险提示、账号信息授权、认证服务器、Web 端口、审计日志。
4. 改端口会重启服务：新端口被占用时会自动向上顺延（最多试 10 个），控制台提示的是**真正生效**的地址。

## 健壮性与交互（优化批次）

- **端口自动回退**：`WebAccessService.start()` 从偏好端口起最多试 10 个；保存端口前先用临时监听探出可用端口，
  因此设置页回包的 `newURL` 和实际监听端口一致，不会出现"提示 8765、服务其实在 8766"。实际端口会写回设置。
- **HEAD 支持**：静态页面、SDK、图标、API 都接受 `HEAD`，只回头部不带 body，方便代理与浏览器预检。
- **图标**：占位图按 `appId` 做 FNV 哈希派生色相（同一应用配色稳定、不同应用可区分），
  `Cache-Control: public, max-age=86400`，`iconURL` 带 `?v=<installedAt>` 做版本化，控制台不再拼随机参数。
- **令牌轮换**：`POST /api/token/rotate` 立刻作废旧令牌，回包带新 token/accessURL 并显式 `Set-Cookie` 种新令牌；
  控制台「重新生成」有二次确认，轮换后当前浏览器无感续用。
- **库变更广播 + 自动刷新**：导入 / 更新 / 卸载 / 商店安装后向 `kinter.webaccess` 追加 `library.changed`；
  控制台用长轮询 `/api/poll?appId=kinter.webaccess` 监听，切回页面（`visibilitychange`）也会刷新。
- **宿主实时横幅**：App 顶层悬浮横幅显示 Web 端"正在干什么"（正在运行「设备信息」/ 正在调用能力 camera.chooseImage /
  正在导入安装包…），25 秒没有真实操作自动收起（控制台的轮询不算，页面开着也不会常驻）；点横幅可直接打开「Web 端访问」设置，右侧「踢出」按钮立即收回控制权
  （作废令牌 + 清空 Web 小程序会话，旧链接一律 401）。
- **Web 原生相机 / 麦克风**：`camera.chooseImage`、`microphone.start/stop` 先让设备做授权判定
  （manifest、用户禁用、安全模式、权限策略），通过后由浏览器 `getUserMedia` / `MediaRecorder` 采集，
  照片和录音以 data URL 返回，可直接在页面里预览；浏览器不可用时回退到设备能力。
- **PWA**：`/manifest.webmanifest` + `/sw.js` + 192/512 图标，控制台「设置 → 关于 → 安装到桌面」；
  Service Worker 只缓存控制台外壳，接口、SDK、小程序页面始终走网络。局域网 HTTP 地址没有 SW 权限，
  `localhost` 或 HTTPS 下才启用离线缓存。
- **Web 端注销**：设置页「会话 → 退出 Web 控制」调用 `POST /api/logout`，立即更换令牌并清掉 HttpOnly cookie，
  页面切成「已退出 Web 控制」整页提示；App 横幅同步显示「Web 端已退出」，点 × 关闭提示。
- **控制台细节**：标签栏与信息按钮改为内联 SVG；应用库有独立「刷新」；设置里 `launchMode=custom` 时
  才显示「指定应用 / 自定义参数」并随保存提交；关于页版本读 `/api/meta`；商店区分「打开 / 更新 / 获取」
  并给可更新条目加徽标；文件大小按 B/KB/MB 自适应，按钮有 `:disabled` 态。

## 限制

- HTTP/1.1 单请求单连接（`Connection: close`），请求体只支持 `Content-Length`，不支持 chunked；
  请求体上限 40 MB（ZIP 用），长任务（`/api/invoke`、导入、预览、商店安装/刷新）超时 180 秒。
- 页面里的 `camera` / 录音等系统权限仍受浏览器与设备双重限制。
- 事件推送是长轮询（`wait` 上限 25 秒），不是 WebSocket；断线后客户端自动重连。
- 服务不对外网暴露；如需跨网络访问，请自行用隧道，并注意令牌泄露风险。

## 资源同步与已知问题

### kinter-for-web 资源副本缺 app.js（已知问题，待统一同步）

- `HostApp/Resources/web/kinter-for-web/index.html` 引用了 `app.js`，但当前该目录副本中**没有 `app.js`**（仅有 index.html / app.css / bridge.js / icon.png / ktml.js / wx.js / zip.js）。补齐之前，经本地 HTTP 服务打开该控制台时 `app.js` 会返回 404，页面交互脚本无法加载。
- 该副本由独立工程维护，**不要在本仓库内手补或改这个目录**；统一从独立副本同步：
  - 源目录：`/Users/mawenhao/Doubao/chats/2026-11-13/new-chat/KinterForWeb`
  - 需复制文件：`index.html`、`app.css`、`app.js`、`bridge.js`、`wx.js`、`ktml.js`、`zip.js`、`icon.png`
  - 目标目录：`HostApp/Resources/web/kinter-for-web/`
- 同步后请确认 `index.html` 引用的全部本地资源在目标目录都存在，避免再次出现 404。

### 本次安全加固引入的行为变化

- App 进入后台时会停止本地服务并作废旧访问令牌；回前台后按上次「自动启动」偏好恢复，旧浏览器链接需重新通过新地址 / 令牌进入。
- 跨源（Origin 与 Host 不一致）的预检与接口请求一律返回 403；控制台页面与接口同源，不受影响。
- 静态资源与接口响应统一带上 `X-Frame-Options: DENY`、`Referrer-Policy: no-referrer`、`Content-Security-Policy: frame-ancestors 'none'; base-uri 'self'`、`X-Content-Type-Options: nosniff`。
