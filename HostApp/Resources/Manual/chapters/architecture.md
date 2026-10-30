# 整体架构与请求链路

## 五层架构

```
小程序（ZIP：manifest.json + HTML/KTML + JS）
        ↓
SDK 层（wx.js Promise API + ktml.js 模板编译）
        ↓
桥接层（BridgeMessageHandler，WKWebView messageHandler）
        ↓
能力网关（CapabilityGateway，每会话独立实例）
        ↓
Provider 层（45 个能力，每会话全新实例）
```

## 完整调用链路

```
HTML 按钮点击
  → wx.chooseImage({count:1})
  → postMessage 到 webkit.messageHandlers.bridge
  → BridgeMessageHandler.didReceive
  → 判断模块：router/store/auth/app/popup/permission 直通，其余走网关
  → CapabilityGateway.invoke(module, method, params)
  → 五道安检（manifest → 禁用 → L3 → 区域 → 权限）
  → Provider.invoke
  → 原生 API
  → Result 回传
  → window.__wxBridgeCallback(callbackId, payload)
  → Promise resolve/reject
```

## 各层职责

| 层 | 关键文件 | 职责 |
|---|---|---|
| JS SDK | `SDK/wx.js` | Promise 封装，callbackId 配对，30s 超时 |
| 模板 | `SDK/ktml.js` | KTML → DOM，插值转义 |
| 桥接 | `BridgeMessageHandler.swift` | JS↔原生唯一通道，事件批量推送 |
| 网关 | `CapabilityGateway.swift` | 五道安检 + 审计 |
| Provider | `Providers/*.swift` | 45 个能力的具体实现 |

## 关键设计

**1. 每会话独立 Provider**
`registry.makeFreshProviders()` 为每个 Gateway 创建全新实例，多窗口并行时状态不串扰。

**2. 六条绿色通道**
`router`、`store`、`auth`、`app`、`popup`、`permission` 不走网关——它们是宿主自身逻辑，不是小程序能力。

**3. 事件批量推送**
同一 RunLoop 内的事件攒成一批，用 `window.__wxEmitBatch` 一次注入，避免 websocket/networkWatch 高频事件刷爆 WebView。

**4. 回调配对**
JS 侧 `pending[callbackId]` 保存 resolve/reject，原生回传时按 ID 找回。
