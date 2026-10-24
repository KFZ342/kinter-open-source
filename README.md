# Kinter

Kinter 是一个面向 iOS 的小程序宿主框架，允许开发者以 ZIP 包形式分发和运行小程序，并通过统一的 `wx.*` API 调用系统原生能力。它强调安全边界、能力声明、隔离治理和可扩展性，提供从页面渲染、路由、能力网关到商店分发的一整套技术栈。

![Platform](https://img.shields.io/badge/Platform-iOS%2016%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-AGPL--3.0-green)
![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen)

## 项目定位

Kinter 的核心目标不是单一 App，而是一套“原生宿主 + 小程序生态运行时”。

- 小程序以 ZIP 包安装
- 页面可使用 HTML 或 KTML 编写
- JavaScript 通过 `wx.*` Promise API 调用宿主能力
- 每个能力都需要在 `manifest.json` 中显式声明
- 能力接入以 L0/L1/L2 等级分层，并在能力网关中做权限、地区、系统权限、异常隔离和审计
- 支持多实例多窗口、页面栈路由、商店源管理、应用发布与 AI 生成小程序

一句话理解：Kinter 是一套“将小程序能力封装进 iOS 宿主环境”的高扩展原生框架。

## 克隆项目

```bash
git clone https://github.com/KFZ342/kinter-open-source.git
cd kinter-open-source
```

如果你不想用 Git，也可以直接在 GitHub 页面点击 `Code` → `Download ZIP`。

## 产品特性

- 45 项原生能力
  - 按 L0/L1/L2 分级管理
  - 未声明能力的调用会被拒绝
- 能力网关
  - 声明校验
  - 区域与系统权限检查
  - ObjC 异常隔离
  - 每个会话独立实例，避免状态串扰
- KTML 模板引擎
  - `column` / `text` / `for` / `if` 声明式组件
  - `{{ }}` 数据绑定
  - 自动 HTML 转义
- 页面栈路由
  - 多页导航
  - 参数传递
  - 返回栈管理，最多 10 层
- 多实例多窗口
  - 同一设备中可并行运行多个应用实例
  - 彼此互不干扰
- AI 生成小程序
  - 基于 OpenAI 兼容接口
  - 自动根据自然语言生成小程序包并迭代修改
- 商店与分发
  - 支持多源聚合
  - 版本比较、SHA256 校验与下载
  - 可发布到自建服务器或静态商店源
- 系统集成
  - Live Activity
  - Siri 快捷指令
  - Spotlight 索引
  - App 间调用
- 崩溃防护
  - 对能力调用做异常隔离
  - 避免单个能力异常拖垮宿主 App

## 架构概览

```text
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

从工程结构上看，Kinter 主要可以分成以下层次：

1. JavaScript SDK 层
   - `SDK/wx.js`：完成 `wx` API 抽象，提供 Promise 风格调用
   - `SDK/ktml.js`：模板编译器，把声明式 KTML 转成 DOM

2. 宿主运行时层
   - `HostApp/`：核心应用环境，负责页面、路由、权限和能力调用

3. 能力治理层
   - `CapabilityGateway`、`Provider`、权限策略与审计机制
   - 统一接收各类能力请求并做安全控制

4. 分发与生态层
   - `StoreTools/`：静态商店源构建
   - `DemoApps/`：示例包与测试应用
   - `Tools/`：工程生成与打包脚本

## 仓库结构

```text
ActivityWidget/      Live Activity Widget Extension
DemoApps/            示例小程序（ZIP + 源文件，可导入宿主）
docs/                文档：CAPABILITIES.md / KTML.md / WX_API.md
HostApp/             宿主 App：Runtime / Core / AI / Auth / UI / Intents / Store
Kinter.xcodeproj     Xcode 工程
SDK/                 wx.js（桥接 SDK） / ktml.js（模板编译器）
StoreTools/          静态商店源构建工具（build_index.py）
Tools/               xcodegen、未签名 IPA 构建脚本、API 列表生成器
SIGNING.md           自签安装指引
LICENSE              AGPL-3.0
README.md            项目说明
```

## 关键能力清单（45 项）

| 分组 | 能力（级别） |
|---|---|
| 媒体与位置 | camera(L1) · photo(L1) · microphone(L1) · speech(L1) · location(L1) · locationWatch(L1) · videoRecord(L1) · qrScan(L1) · savePhoto(L1) |
| 设备与系统 | deviceInfo(L0) · battery(L0) · network(L0) · motion(L1) · bluetooth(L1) · bluetoothScan(L1) · vibrate(L0) · brightness(L0) · screenAwake(L0) |
| 系统集成 | contacts(L1) · calendar(L1) · reminder(L1) · notification(L1) · share(L0) · openURL(L0) · communication(L0) |
| 数据与网络 | storage(L0) · clipboard(L0) · clipboardImage(L0) · files(L0) · http(L0) · websocket(L0) · upload(L0) · networkWatch(L0) |
| 扩展与进阶 | tts(L0) · qrGenerate(L0) · ocr(L0) · audio(L0) · image(L0) · pdf(L0) · print(L0) · biometric(L1) · health(L2) |
| 账号与生态 | account(L0) · spotlight(L0) · liveActivity(L2) |

说明：
- L0：无授权
- L1：系统弹窗授权
- L2：需要 entitlement

只有在 `manifest.json` 中声明的能力才会被允许访问；未声明的能力调用通常返回 `capability_not_declared`。

## 快速开始

### 1. 安装依赖

```bash
brew install xcodegen
```

### 2. 生成 Xcode 工程

```bash
xcodegen generate --spec Tools/project.yml
```

### 3. 打开并运行

在 Xcode 中打开 `Kinter.xcodeproj`，选择你的设备，然后按 `Cmd + R` 运行。

### 4. 直接安装 IPA（可选）

开箱即用的未签名 IPA（含最新音乐播放能力）发布在 GitHub Releases：

**下载：[Releases 页面](https://github.com/KFZ342/kinter-open-source/releases/latest)（下载 `Kinter-unsigned-*.ipa`）**

安装方式：
- TrollStore：直接安装
- SideStore / AltStore / Sideloadly：自签安装
- 首次启动前需要打开：设置 → 隐私与安全性 → 开发者模式

如需自行构建：

```bash
chmod +x Tools/build_unsigned_ipa.sh
./Tools/build_unsigned_ipa.sh Release
```

产物默认生成到 `build/Kinter-unsigned.ipa`。

## 小程序开发示例

一个小程序通常是一个 ZIP 包，包含：

```text
manifest.json
index.html
pages/...
```

### manifest.json 示例

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

### HTML 方式

```js
wx.chooseImage({ count: 1 })
  .then(res => console.log(res.tempFilePaths))
  .catch(err => console.error(err.code))
```

### KTML 方式

```xml
<column padding="20" gap="16">
  <text size="xxl" weight="bold">{{ title }}</text>
  <for each="item in items" key="id">
    <row>
      <text>{{ item.name }}</text>
      <text color="muted">¥{{ item.price }}</text>
    </row>
  </for>
</column>
<script>
var title = '水果';
var items = [{ id: 1, name: '苹果', price: '8.5' }];
</script>
```

这说明 Kinter 的小程序开发体验同时兼容：
- 传统 HTML + JS
- 声明式 KTML 模板

## JavaScript SDK

`SDK/wx.js` 是整个项目的桥接层，所有能力都通过 `wx` 对象暴露给页面脚本：

```js
wx.http({ url: 'https://example.com/api' })
  .then(res => console.log(res))
  .catch(err => console.error(err))
```

SDK 设计特点：
- 统一 Promise API
- 能力调用前置能力声明检查
- 宿主和页面逻辑解耦
- 运行时错误可被网关统一处理

### iOS 原生权限深度集成

小程序可通过 `wx.*` 权限 API 查询、申请 iOS 系统权限，并在被拒后引导用户到系统设置开启：

```js
// 查询所有权限状态（微信风格 authSetting）
wx.getSetting().then(res => console.log(res.authSetting))

// 查询单个权限细分状态
wx.getPermissionStatus({ permission: 'scope.camera' })
  .then(res => console.log(res.status)) // authorized / denied / notDetermined / restricted / limited / unsupported

// 申请授权（弹系统授权框）
wx.authorize({ permission: 'scope.camera' }).then(res => console.log(res.status))

// 打开本 App 的系统设置页（权限被拒后引导用户）
wx.openSetting()
```

支持的 `scope.*` 权限：`scope.camera`（相机）、`scope.record`（麦克风）、`scope.userLocation`（定位）、`scope.album`（相册）、`scope.writePhotosAlbum`（保存相册）、`scope.addressBook`（通讯录）、`scope.calendar`（日历）、`scope.reminders`（提醒事项）、`scope.notification`（通知）、`scope.bluetooth`（蓝牙）、`scope.werun`（运动）、`scope.speech`（语音识别）、`scope.faceId`（Face ID）、`scope.health`（健康步数）。

对应原生实现位于 `HostApp/Runtime/Gateway/PermissionManager.swift`，统一封装 AVFoundation / CoreLocation / Contacts / EventKit / UserNotifications / CoreBluetooth / CoreMotion / Speech / LocalAuthentication / HealthKit / Photos 授权链路。

## 安全模型

Kinter 并不是“开放式 JS 沙箱”那么简单，而是更偏向“有边界的能力执行平台”。

主要安全控制包括：

- manifest 权限声明
- L0/L1/L2 能力分级
- 地区与系统权限检查
- 每个会话单独的 `CapabilityGateway` 实例
- ObjC 异常隔离
- 审计日志与统一错误封装

这意味着：
- 页面脚本本身不能无限制访问系统能力
- 能力调用需要在声明、权限和安全策略下放行
- 即使某一项能力失败，也不会直接拖垮宿主应用

## 商店、应用分发与部署

Kinter 既支持本地部署，也支持静态商店源。`StoreTools/` 允许脚本生成 `index.json`，用来做应用列表和版本分发。

```bash
python3 StoreTools/build_index.py
```

商店源结构示意：

```text
apps/
  app-name/
    manifest.json
    icon.png
    1.0.0.zip
index.json
```

这样做的好处是：
- 无需复杂后端
- 可用 GitHub Pages / jsDelivr 作为静态源
- 客户端通过拉取 `index.json` 完成应用列表同步

## 账号与服务端

开源版本身不内置完整后端，但项目已设计了账号与应用发布方案：

```text
POST /api/register
POST /api/login
GET  /api/me
POST /api/logout
POST /api/apps/publish
```

这些接口用于：
- 用户鉴权
- 应用发布
- 商店元数据更新
- 分发资源管理

建议的生产环境安全要求：
- 密码使用哈希与盐
- Token 定期过期
- ZIP 解包时防止路径穿越与炸弹
- HTTPS 部署

## 代码贡献方式

欢迎参与贡献：

- 新增原生能力：在 `HostApp/Runtime/Gateway/Providers/` 中增加 Provider，并在能力注册中心中注册
- 新增 JS API：修改 `SDK/wx.js`，并同步生成 API 清单
- 文档增强：补充到 `docs/` 下对应能力说明文件

## 已知限制

- 同层渲染未实现：部分能力仍采用全屏 picker 等形式
- 页面脚本与 KTML 表达式在全局作用域执行，安全边界主要依赖宿主网关
- 桥接层统一有 30s 超时，超时后保证 Promise 不挂起，但长任务可能仍在后台继续
- 未配置认证服务器时，账号登录、应用发布等能力不可用

## 许可证

本项目使用 [GNU AGPL-3.0](LICENSE)。

简要说明：
- 允许商用、修改和分发
- 但如果将本项目或其衍生版本用于商业产品/服务，必须以相同协议公开对应源代码

## 一句话总结

Kinter 是一个“高安全边界、高能力抽象、可扩展的 iOS 小程序宿主框架”，它把应用分发、原生能力、模板渲染、权限控制和商店生态统一进一套架构中，目标是把小程序运行时做成真正可用于生产的 iOS 平台能力层。
