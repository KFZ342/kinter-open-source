# 平台定位与快速上手

## Kinter 是什么

Kinter 是一套 **iOS 小程序宿主框架**，让开发者以 ZIP 包分发小程序，通过统一的 `wx.*` API 调用系统原生能力。

一句话理解：**把微信小程序那套运行机制（ZIP 分发 + wx API + manifest 权限声明 + 能力网关隔离）从微信里剥离出来，做成任何 iOS App 都能集成的宿主框架。**

核心目标不是单一 App，而是「原生宿主 + 小程序生态运行时」。

## 五件套

| 微信生态 | Kinter 对应 |
|---|---|
| 微信 App | HostApp（宿主） |
| 小程序 SDK | SDK/wx.js + BridgeMessageHandler |
| 开放平台权限/审核 | CapabilityGateway + manifest.json |
| 小程序商店 | AuthServer + StoreManager |
| 小程序开发者工具 | AI Agent（自然语言生成） |

## 能做什么

- **45 项原生能力**：相机、相册、定位、蓝牙、健康、TTS、音乐、通知、PDF、打印、Spotlight、实时活动等
- **能力分级管控**：L0 无授权 / L1 系统弹窗 / L2 需 entitlement / L3 高危（默认拦截）
- **KTML 模板引擎**：声明式组件 + 数据绑定 + 自动 HTML 转义
- **页面栈路由**：最多 10 层
- **多实例多窗口**：同设备并行跑多个小程序，互不干扰
- **AI 生成小程序**：自然语言 → JSON → ZIP → 直接运行
- **商店与分发**：多源聚合、SHA256 校验、付费小程序（平台抽成 7%）
- **崩溃防护**：ObjC 异常隔离，单个能力崩溃不拖垮宿主

## 快速上手（三步）

### 1. 装依赖并生成工程

```bash
brew install xcodegen
xcodegen generate --spec Tools/project.yml
```

### 2. 打开运行

在 Xcode 打开 `Kinter.xcodeproj`，选设备，Cmd+R。

### 3. 用 AI 生成第一个小程序

打开宿主 → 点 AI 管家 → 输入「做一个番茄钟，红色主题，25 分钟计时」→ AI 自动生成 → 说「安装它」→ 应用库出现 → 点开即运行。

## 直接用 AI 的一句话

> 「做一个待办清单，要能加提醒，界面用暗黑模式，做完之后卖 6 块钱上架。」

AI 会自己规划：`generate` 写代码 → `install` 安装 → `publish` 上架，全程不用写一行代码。

## 已知限制

- 同层渲染未实现，部分能力走全屏 picker
- 页面脚本与 KTML 表达式同权，安全边界靠宿主网关
- 桥接统一 30 秒超时
- 未配置认证服务器时，登录/发布不可用
