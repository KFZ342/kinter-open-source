# 独家功能（别人没有的）

Kinter 宿主内置三项其它小程序平台没有的能力。它们不需要任何服务器，
开箱即用。

## 1. 跨窗口实时联动 LiveSync（多开实例互通）

微信/支付宝小程序都是单实例运行：同一时间只跑一份，两个小程序之间
不可能实时互相传数据。Kinter 的多任务窗口让多个小程序**并排同时运行**，
LiveSync 让它们实时联动。

### API

| API | 说明 |
|---|---|
| `wx.broadcast({topic, payload})` | 向其它所有窗口广播事件 |
| `wx.onBroadcast(topic, handler)` | 订阅其它窗口的广播 |
| `wx.setSharedValue({key, value})` | 写入共享值，其它窗口实时收到变更 |
| `wx.getSharedValue({key})` | 读取共享值 |
| `wx.listSharedValues({})` | 列出全部共享值 |
| `wx.removeSharedValue({key})` | 删除共享值并通知 |
| `wx.onSharedValueChange(key, handler)` | 订阅共享值变更 |

### 示例：两个窗口协作

窗口 A（控制台）：
```js
wx.setSharedValue({ key: 'mode', value: 'night' });
wx.broadcast({ topic: 'refresh', payload: { source: 'a' } });
```

窗口 B（展示页）：
```js
wx.onSharedValueChange('mode', function (e) {
  // e = { key, value, from }
  document.body.style.background = e.value === 'night' ? '#111' : '#fff';
});
wx.onBroadcast('refresh', function (e) {
  // e = { topic, payload, from }
  loadData(e.payload.source);
});
```

典型玩法：控制面板改设置 → 展示窗口实时换肤；主窗口改数据 →
详情窗口自动刷新。多窗口 + 实时联动 = 微信生态里不可能存在的体验。

## 2. 小程序内 AI 助手 wx.askAI

微信/支付宝的小程序页面里**没有 AI**。Kinter 的小程序页面可以随时唤起
宿主配置好的 AI 模型（设置 → 模型），直接问答，还能拿到可执行的 wx 代码。

### API

```js
const res = await wx.askAI({
  question: '帮我写个倒计时组件',
  context: '当前页面是计时器，主题深色'   // 可选，给 AI 的上下文
});
// res = { answer: '…中文回答…', code: '…可选的可执行 wx 代码…' }
```

- `answer`：AI 的中文回答
- `code`：可选的 ```wx 代码块（只允许 wx.* API，宿主不自动执行，
  由小程序开发者决定如何使用，杜绝注入风险）

### 玩法

- 页面内置"AI 帮助"按钮，用户点一下直接问答
- 开发者问 AI 要代码片段，粘贴到自己的页面里
- 页面按用户输入动态问 AI（如"帮我把这个列表按价格排序"）

## 3. 性能监视浮层 DevHUD

微信开发者工具有性能面板，但只在桌面 IDE 里；C 端用户根本看不到自己
运行的页面多快多慢。Kinter 把性能监视**做进宿主运行界面**：

- 小程序运行页导航栏点 **仪表盘图标**，实时悬浮显示：
  - **FPS**（流畅 / 可接受 / 卡顿 三档着色）
  - **桥接调用次数与失败数**
  - **JS 错误累计**
  - **联动窗口在线数**
  - **运行时长**

## 权限声明

在 manifest 的 `capabilities` 中声明即可使用（均 L0）：

```json
{
  "capabilities": {
    "sharedbus": { "level": "L0" },
    "ai":        { "level": "L0" }
  }
}
```
