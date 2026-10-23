# 自签安装指引

适用于未签名 IPA 分发。按设备系统版本选方式。

## 方式一：TrollStore（推荐，永久签）

适用：iOS 14.0–16.6.1、17.0 部分版本。

1. 安装 TrollStore（参考 trollstore.app）
2. 把 IPA 传到设备（AirDrop / 文件 App）
3. 用 TrollStore 打开 IPA，自动安装
4. 永久有效，无需续签

## 方式二：SideStore（自动续签）

适用：任意版本，首次需电脑注入。

1. 电脑安装 SideStore 配套工具（AltServer）
2. 设备信任电脑，完成首次安装
3. 之后每 7 天自动续签，无需连电脑

## 方式三：AltStore / Sideloadly（手动续签）

适用：任意版本，兜底方案。

1. 电脑安装 AltStore 或 Sideloadly
2. 用 Apple ID 签名安装 IPA
3. 每 7 天手动刷新一次

## 必做：开启开发者模式

iOS 17+ 安装后需开启：

设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启设备

不开启会导致 App 闪退打不开。

## 常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| 安装后闪退 | 未开开发者模式 | 按上文开启 |
| 提示未受信任 | 未信任描述文件 | 设置→通用→VPN与设备管理→信任 |
| 7 天后打不开 | 签名过期 | 用原工具重新签名 |
| bridge_unavailable | wx.js 未注入 | 确认 SDK/wx.js 在 Bundle Resources |
