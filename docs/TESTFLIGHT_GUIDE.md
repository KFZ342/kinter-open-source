# Kinter · TestFlight 分发完整流程

> 依据 Apple 官方文档整理（App Store Connect Help / Xcode 帮助 / Apple Developer Forums）
> 适用版本：Kinter 1.2.0 (3)，Bundle ID `com.kinter.host`

## 阶段 0：一次性前置准备（约 30 分钟）

| # | 事项 | 说明 |
|---|---|---|
| 1 | 注册 Apple Developer | developer.apple.com，$99/年，需实名（身份证/护照） |
| 2 | 开发者后台添加 App ID | developer.apple.com/account → Identifiers → 注册 `com.kinter.host`，**勾选 HealthKit + NFC Tag Reading**（缺了上传会报 ITMS 校验失败） |
| 3 | Xcode 登录 | Xcode → Settings → Accounts → 添加你的 Apple ID（加入 Membership 后显示 Team） |
| 4 | 工程选签名 Team | 打开 `Kinter.xcodeproj` → Kinter target → Signing & Capabilities → Automatically manage signing → 选 Team；**Widget 扩展 target 同样操作一次** |
| 5 | 准备测试设备 | 至少一台真机 iPhone/iPad（TestFlight 不支持模拟器安装） |

## 阶段 1：构建并上传（每次发版重复）

```
1. 构建前版本号确认：HostApp/App/Info.plist 里 CFBundleShortVersionString（如 1.2.0）与
   CFBundleVersion（构建号，每次上传必须递增，如 3→4）

2. 命令行一键构建（脚本已就绪）：
   ./Tools/build_testflight.sh
   或 Xcode GUI：Product → Archive（Destination 选 "Any iOS Device (arm64)"）

3. Xcode → Window → Organizer → 选中最新 Archive → 右侧 "Distribute App"
   → 选 "App Store Connect" → Upload
   （Xcode 会自动签名、校验、上传，约 5-15 分钟）

   或用命令行上传（需专用密码，Apple ID → Sign-in & Security → App-Specific Passwords 生成）：
   xcrun altool --upload-app -f Kinter.ipa -t ios -u 你的AppleID -p 专用密码
```

上传成功的判定：Xcode 显示 "Upload Success"，邮箱收到 App Store Connect 通知。

## 阶段 2：App Store Connect 配置（首次必做）

1. **新建 App**（App Store Connect → My Apps → +）：选平台 iOS，填名称、主要语言、Bundle ID、版本 1.2.0
2. **App 信息**：填 1024×1024 图标（无 alpha 通道）、副标题、关键词、隐私政策 URL（可先用占位）
3. **加密合规**：TestFlight 页/构建详情里选"否/豁免"（App 仅用标准 HTTPS 传输即可豁免）
4. **等待构建处理**：上传后状态 "Processing" 通常 **5-30 分钟**；就绪会收到邮件。
   ⚠️ 超过 24 小时仍 Processing → 联系 Apple（构建版本最长可用 90 天，到期需重新上传）

## 阶段 3：邀请测试员

### 内部测试组（推荐先用这个，免 Beta 审核，上限 100 人）
- App Store Connect → TestFlight → 内部测试
- 建组 → 添加成员（Apple ID 邮箱）→ 勾选构建版本
- 成员手机装 TestFlight App 后即可看到并安装，**无需任何审核**

### 外部测试组（上限 10000 人，需要 Beta App Review）
- TestFlight → 外部测试 → 建组 → 添加测试员邮箱/公开链接
- 需填写：Beta 版 App 描述 + Beta 审核信息（登录账号说明等）
- 提交审核：Apple 人工过一遍（主要查明显违规/崩溃，通常 1-3 天）
- 通过后生成公测链接：`testflight.apple.com/join/XXXX`，可公开分享，扫码即加入

## 阶段 4：测试员侧

1. App Store 下载 TestFlight（免费）
2. 点邀请邮件/链接 → "开始测试" → 安装 Kinter
3. 反馈：App 内摇一摇或 TestFlight 里评分（1-5 星 + 截图），开发者可在 App Store Connect 查看

## 常见坑与排查

| 现象 | 原因/处理 |
|---|---|
| 上传报 `ITMS-90xxx` 签名错误 | 证书/Provisioning Profile 问题；确认 Team 已选、证书未过期 |
| 上传报 capability 缺失 | 后台 App ID 没勾 HealthKit/NFC；重勾后重新生成描述文件 |
| Processing 卡住 >24h | 联系 Apple（可能是符号表/崩溃日志处理卡住） |
| 构建过期 | TestFlight 构建 90 天过期，发新版要递增构建号重新上传 |
| 测试员收不到邀请 | 确认其 Apple ID 邮箱；外部测试员需先过 Beta 审核 |
| 真机安装提示不受信任 | 正常，iOS 会要求"设置 → 通用 → VPN与设备管理 → 信任开发者证书" |
| HealthKit 在模拟器不可用 | 正常，健康数据仅真机 |

## 里程碑速览

```
注册账号 → 后台配 App ID/capability → Xcode 选 Team
  → Archive → Distribute → 上传 App Store Connect
  → Processing(5-30min) → 内部测试组(免审，今天可测)
  → 外部测试组(Beta 审核 1-3 天) → 公开链接分发
```
