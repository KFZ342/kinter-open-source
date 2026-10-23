# Kinter

在 iOS 上运行小程序、调用原生能力的宿主框架。**极客向、可自签安装、无第三方依赖**。

![Platform](https://img.shields.io/badge/Platform-iOS%2016%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-AGPL--3.0-green)
![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen)

小程序以 ZIP 安装：一个 `manifest.json` 声明能力，页面用 HTML 或 KTML 编写，JS 通过 `wx.*`（Promise API）调用 45 项原生能力——相机、定位、健康、蓝牙、WebSocket、OCR、Live Activity……每项能力都要在 manifest 中声明、经过网关校验才会放行。

## 特性

- **45 项原生能力**，按 L0（无授权）/ L1（系统弹窗）/ L2（需 entitlement）分级
- **能力网关**：manifest 声明 → 级别 → 地区 → 系统权限 → ObjC 异常隔离 → 审计，每会话独立实例
- **KTML 模板**：`<column>/<text>/<for>/<if>` 声明式组件 + `{{ }}` 插值，编译为 DOM，自动 HTML 转义
- **页面栈路由**：多页导航、参数传递、返回栈（上限 10 层）
- **多实例多窗口**：同一台设备并行运行多个小程序，状态互不串扰
- **AI 生成小程序**：OpenAI 兼容接口，根据自然语言生成完整小程序包并迭代修改
- **商店订阅**：多源聚合、版本比较、SHA256 校验下载；支持发布到自建服务器
- **系统集成**：Live Activity（灵动岛）、Siri 快捷指令、Spotlight 索引、App 间调用
- **崩溃防护**：ObjC 异常隔离、UIKit 呈现安全包装，单个能力失败不拖垮宿主

## 架构

```
小程序 JS (wx.js / ktml.js)
   ↓ postMessage
WKWebView 桥接层 (BridgeMessageHandler)
   ├─ router / store / auth / app / popup 原生直通
   ↓
能力网关 (CapabilityGateway，每会话独立实例)
   ├─ manifest 声明校验
   ├─ L0~L3 级别检查
   ├─ 地区可用性检查
   ├─ 系统权限检查 (PermissionPolicy)
   ├─ ObjC 异常隔离
   └─ 审计日志
   ↓ 路由
Provider（45 个能力，每会话全新实例）
```

外围模块：`AppLibrary`（安装库持久化）、`PackageInstaller`（ZIP 校验安装）、`StoreManager`（商店源/更新/下载）、`GitHubAPI`（仓库/Pages 发布）、`StorePublisher`（发布到自建服务器）、`AIClient + AIGenerator`（AI 生成小程序）、`KinterAuthManager`（账号）、`PageRouter`（页面栈）、`KTMLCompiler`（模板编译）、`ActivityWidget` / `Intents` / `Spotlight`。

## 仓库结构

```
ActivityWidget/      Live Activity Widget Extension
DemoApps/            示例小程序（ZIP + 源文件，可导入宿主）
docs/                文档：CAPABILITIES.md（能力详解）、KTML.md（模板语法）、WX_API.md（wx API 参考）
HostApp/             宿主 App：Runtime（网关/渲染/路由）、Core（安装/商店）、AI、Auth、UI、Intents、Store
Kinter.xcodeproj     Xcode 工程
SDK/                 wx.js（桥接 SDK）、ktml.js（模板编译器）
StoreTools/          静态商店源构建工具（build_index.py）
Tools/               xcodegen 配置、未签名 IPA 构建脚本、API 列表生成器
SIGNING.md           自签安装指引
```

## 能力清单（45 项）

| 分组 | 能力（级别） |
|---|---|
| 媒体与位置 | camera(L1) · photo(L1) · microphone(L1) · speech(L1) · location(L1) · locationWatch(L1) · videoRecord(L1) · qrScan(L1) · savePhoto(L1) |
| 设备与系统 | deviceInfo(L0) · battery(L0) · network(L0) · motion(L1) · bluetooth(L1) · bluetoothScan(L1) · vibrate(L0) · brightness(L0) · screenAwake(L0) |
| 系统集成 | contacts(L1) · calendar(L1) · reminder(L1) · notification(L1) · share(L0) · openURL(L0) · communication(L0) |
| 数据与网络 | storage(L0) · clipboard(L0) · clipboardImage(L0) · files(L0) · http(L0) · websocket(L0) · upload(L0) · networkWatch(L0) |
| 扩展与进阶 | tts(L0) · qrGenerate(L0) · ocr(L0) · audio(L0) · image(L0) · pdf(L0) · print(L0) · biometric(L1) · health(L2) |
| 账号与生态 | account(L0) · spotlight(L0) · liveActivity(L2) |

级别：**L0** 无授权 ｜ **L1** 系统弹窗授权 ｜ **L2** 需 entitlement。每个能力在 manifest 中声明后才会放行，未声明的调用返回 `capability_not_declared`。详细说明见 [docs/CAPABILITIES.md](docs/CAPABILITIES.md)。

## 快速开始

### 1. 生成 Xcode 工程

```bash
brew install xcodegen
xcodegen generate --spec Tools/project.yml
```

### 2. 真机运行

Xcode 打开 `Kinter.xcodeproj`，选中你的设备，Signing 选 Personal Team，Cmd+R。

### 3. 直接安装预构建 IPA（省去编译）

仓库已附带开箱即用的未签名 IPA（含最新音乐播放能力）：

**下载：[Releases/Kinter-unsigned-1.1.0.ipa](Releases/Kinter-unsigned-1.1.0.ipa)**

安装方式（任选其一）：
- **TrollStore**：直接安装（设备系统版本需在支持区间）
- **SideStore / AltStore / Sideloadly**：自签安装（需 Apple ID，7 天续签一次）
- 安装后首次启动前：设置 → 隐私与安全性 → **开发者模式** 开启

如需自己构建：

```bash
chmod +x Tools/build_unsigned_ipa.sh
./Tools/build_unsigned_ipa.sh Release
```

产物在 `build/Kinter-unsigned.ipa`，自签安装指引见 [SIGNING.md](SIGNING.md)（TrollStore / SideStore / AltStore）。

## 写一个小程序

一个小程序 = 一个 ZIP：

```
manifest.json      能力声明
index.html         入口页面（或 index.ktml）
pages/...          更多页面
```

`manifest.json` 示例：

```json
{
  "appId": "com.example.hello",
  "version": "1.0.0",
  "name": "示例应用",
  "minHostVersion": "1.0.0",
  "pages": ["index"],
  "capabilities": {
    "deviceInfo": { "level": "L0" },
    "files": { "level": "L0" }
  }
}
```

HTML 页面（经典方式）：

```js
wx.chooseImage({ count: 1 })
  .then(res => console.log(res.tempFilePaths))
  .catch(err => console.error(err.code))
```

KTML 页面（模板 + 脚本分离，`.ktml` 文件，示例见 `DemoApps/ktml-test`）：

```
<column padding="20" gap="16">
  <text size="xxl" weight="bold">{{ title }}</text>
  <for each="item in items" key="id">
    <row><text>{{ item.name }}</text><text color="muted">¥{{ item.price }}</text></row>
  </for>
</column>
<script>
var title = '水果';
var items = [{ id: 1, name: '苹果', price: '8.5' }];
</script>
```

完整语法见 [docs/KTML.md](docs/KTML.md)（模板）与 [docs/WX_API.md](docs/WX_API.md)（wx API 参考）。

JS SDK 清单：`SDK/wx.js`（所有 API 返回 Promise）；能力列表由 `Tools/gen_api_list.py` 从 wx.js 自动生成到 `HostApp/AI/WXAPIList.swift`，改 wx.js 后需重跑。

## 账号与商店服务器

**开源版不内置服务器实现**。账号登录、应用发布、商店订阅依赖自建服务器，构建后在「设置 → 账号 → 认证服务器」填入你的服务器地址。接口契约（社区可据此自建兼容服务）：

```
POST /api/register        {username, password, name?} → {token, user}
POST /api/login           {username, password}        → {token, user}
GET  /api/me              需要 Bearer token            → user
POST /api/logout          吊销 token
POST /api/apps/publish    multipart 上传 ZIP，需 Bearer token → {appId, name, version, sourceURL}
GET  /store/:username/index.json                        → 商店源（StoreTools 格式）
GET  /store/:username/apps/:appId/:version.zip          → 应用包下载
```

安全要求：密码加盐哈希（如 scrypt）、token 定期过期、ZIP 解包防路径穿越与炸弹、HTTPS 部署。

只想发静态商店源也可以完全不用服务器：用 `StoreTools/build_index.py` 生成 index.json，推到 GitHub Pages / jsDelivr 即可。

## 贡献

- 新增能力：在 `HostApp/Runtime/Gateway/Providers/` 加一个 `XxxProvider`，实现 `CapabilityProvider` 协议，在 `CapabilityRegistry.registerBuiltins()` 注册，manifest 即可声明
- 新增 JS API：在 `SDK/wx.js` 加方法，用 `Tools/gen_api_list.py` 重新生成 AI 提示词用的 API 清单
- 文档：能力细节补充到 `docs/CAPABILITIES.md`

## 已知限制

- 同层渲染未实现（相机为全屏 picker）
- 小程序脚本与 KTML 表达式在页面全局作用域执行，安全边界依赖宿主网关而非模板层
- 桥接有 30s 统一超时；超时仅保证 Promise 不挂起，Provider 长任务可能仍在后台运行
- 未配置认证服务器时，账号登录与应用发布不可用（其余能力不受影响）

## License

[GNU AGPL-3.0](LICENSE)（OSI 认证的开源协议）。

一句话理解：**允许商用、修改与分发，但任何人将本项目或其衍生作品用于商业产品/服务时，都必须以相同协议公开对应源代码**（含网络服务场景，见第 13 条）。这是标准 copyleft 条款，公司法务可直接评估，无自定义附加条件。
