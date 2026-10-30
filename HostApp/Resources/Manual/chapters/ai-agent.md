# AI Agent 与生成流程

## ReAct 循环

用户消息 → LLM 推理 → 决定调工具或回复 → 宿主执行 → 结果回灌 → 再推理 → 最终回复。最多 6 轮（`maxAgentRounds`）。

## 13 个工具

| 工具 | 作用 | 参数 |
|---|---|---|
| generate | 生成新小程序 | `{prompt}` |
| iterate | 修改已有小程序 | `{instruction}` |
| install | 安装到应用库 | `{}` |
| publish | 发布到商店 | `{price}` |
| open | 打开运行 | `{appId}` |
| list | 列出已装 | `{}` |
| delete | 删除 | `{appId}` |
| export | 导出 ZIP 并分享 | `{appId?}` |
| qr | 生成二维码 | `{text}` |
| stats | 应用库统计 | `{}` |
| browse | 浏览商店 | `{}` |
| capability | 直连能力网关 | `{api, params}` |
| screenshot | 截屏给 AI 看 | `{}` |

## 输出协议

调工具时**只输出一个 JSON**，不要任何其他文字、不要代码块围栏：

```json
{"tool":"generate","args":{"prompt":"番茄钟"}}
```

聊天/总结时直接输出自然语言。

## 生成流程

1. `generate` 内部调 LLM，用 `AIPrompt.system`（含完整 wx API 规格 + 能力清单 + UI 质量规范）
2. 模型返回 JSON：`{name, appId, version, files:{...}, capabilities:{...}}`
3. `AIGenerator.parse` 容错解析（剥 markdown 围栏）+ 安全校验（路径不能有 `..`、能力 ID 必须在白名单）
4. `writeToDisk` 写临时目录，`icon.svg` 自动渲染成 `icon.png`
5. 返回卡片，用户说“安装”才真正进应用库

## 迭代模式

`iterate` 用 `AIPrompt.iterateSystem`，强调**最小改动**：
- 不重写整个应用，只改用户要求的部分
- 保留所有现有功能
- **appId 必须保持不变**（否则变成新应用）
- version 递增

## 提示词质量规范

`AIPrompt.system` 强制 AI 遵守 27 条硬标准，包括：
- 必须用卡片 UI、圆角 12-16px
- 必须适配深色模式
- 触控目标 ≥ 44pt
- 三态齐备（加载/空/错误）
- 每个 `await` 包 try/catch
- 关键流程打 console.log

## 流式与容错

- SSE 流式输出，边生成边刷新 UI
- 空闲看门狗：90 秒无数据自动中断
- 视觉降级：模型不支持看图时，自动剥离截图重试一次
- 能力白名单：AI 编造的能力 ID 会被剔除
