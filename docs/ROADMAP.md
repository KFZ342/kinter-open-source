# Kinter Roadmap

> 本文件把两代需求合并成一张表：**Pioneer APP Launcher（v0，仅文档稿，已停更）** → **Kinter（在研，有实现）**。
> 状态按代码实测填写，不按 README 自述。最近核对：2026-11-07，`kinter-open-source` @ `172f2e6`。

---

## 一、沿革

| 阶段 | 载体 | 状态 | 留下了什么 |
|---|---|---|---|
| v0 | Pioneer APP Launcher | 只有 README（3 个文件 / 0 行代码 / 1 次提交），已停更 | 完整的产品设想：Web 容器、JSBridge、13 类权限、manifest 规范、ZIP 导入、5 个示例应用、应用商店、调试面板 |
| v1 | Kinter | 129 个 Swift 文件 / 19,313 行 / 50 个原生能力 / 三级安全模式 | v0 设想的大部分落地，并加上了能力网关、KTML、多窗口、商店付费、AI 生成小程序 |

Pioneer 的 README 不再维护，功能演进一律在本仓库进行。

---

## 二、状态总览

### 已有（v0 承诺 + v1 超出）

- WKWebView 容器、`wx.*` Promise 桥、manifest 能力声明强校验
- 50 个原生能力，L0/L1/L2 分级 + 能力网关（声明 / 地区 / 系统权限 / 异常隔离 / 审计）
- 三级安全模式：critical / standard / network + 一次性令牌 + 信任清单 + JSONL 追溯 + 组合规则
- KTML 声明式模板、页面栈路由（≤10 层）、多窗口多实例（Provider 全会话隔离）
- ZIP 包安装（路径穿越 + ZIP 炸弹双校验）、安装预览
- 商店：多源聚合、版本比较、SHA256 校验、付费小程序与抽成口径
- AI 生成小程序（自然语言 → 包 → 迭代修改）
- DevHUD 性能浮层、Live Activity、Spotlight、Siri 快捷指令
- 文档：CAPABILITIES / DEPLOY / KTML / TESTFLIGHT_GUIDE / WX_API / SIGNING / SECURITY_MODE

### 缺口（按优先级）

---

## 三、P0 · 安全债（不定就一直是"安全模式"名不副实）

| # | 事项 | 现状 | 验收口径 |
|---|---|---|---|
| P0-1 | 组合规则改 taint 模型 | 现在是"高危调用后 5 秒内出现外发就拦"，等 6 秒即绕过 | 会话维度打污点标记，窗口内任何外发强制二次确认；单测覆盖"延时外发"用例 |
| P0-2 | 直通模块纳入网关 | `router` / `store` / `auth` / `app` / `popup` / `permission` 在 Bridge 提前 return，只挡了 3 个高危方法 | 至少把 `popup`（可伪装宿主弹窗）、`store`（会话存储读写）纳入拦截与记录 |
| P0-3 | 清掉 `badQuery` | 已从注册表移除、已设 `hardDenied`，代码文件仍在树上 | 物理删除或 `#if` 包裹，防止有人再注册回去 |
| P0-4 | 桥超时与横幅时长对齐 | `wx.js` 桥超时 30s，横幅 8s，用户点慢会导致原调用已 reject、令牌留给下一次 | 令牌绑定单次调用 ID，或在超时后自动作废 |
| P0-5 | 未分级能力补齐 | 50 个能力已分级 27 个，其余"放行但记录" | 全部登记；`auditCoverage` 在 CI 中作为失败条件 |

---

## 四、P1 · 产品化（已完成）

| # | 事项 | 状态 |
|---|---|---|
| P1-1 | 应用收藏 / 评分 / 使用统计 | ✅ `InstalledApp` 增字段（fav/rating/launchCount/lastOpenedAt/totalUsageSeconds），`AppLibrary` 增接口，列表页与配色管理页已接入 |
| P1-2 | 开箱即用示例库 | ✅ `DemoAppsCatalog` 内置 5 个（计算器 / 待办清单 / 秒表 / 单位换算 / 能力导览），首次启动自动写入并注册 |
| P1-3 | `manifest.json` 支持 `iconSymbol` + `iconColor` | ✅ 解析、安装落库、单元格渲染三处打通，无图标文件也能显示彩色 SF Symbol |
| P1-4 | 权限「一键全请求」调试入口 | ✅ DevHUD 增加按钮，串行请求 13 类系统权限并显示进度 |
| P1-5 | README「三十秒看懂」清单 | ✅ README 增「开箱即用」章节（示例表 + 图标写法 + 调试工具） |

## 五、P2 · 生态与分发

| # | 事项 | 说明 |
|---|---|---|
| P2-1 | 应用导出 / 备份 | v0 承诺过 zip 导出、导出全部应用，v1 只有导入 |
| P2-2 | 应用自动更新 | 商店已有多源与版本比较，但缺后台静默更新通道 |
| P2-3 | PWA / WebAssembly 支持 | v0 Roadmap 提过，对"轻应用"生态扩展性最大 |
| P2-4 | 分发与合规路线 | TestFlight / 侧载两套；AGPL-3.0 与商业化抽成存在张力，需单独定夺 |

---

## 六、明确不做

- **幽灵权限（返回假数据）**：防不住行为检测，成本高，已否。
- **依赖私有 API 的沙盒逃逸能力**：`dlopen` + `container_copy_sandbox_token` 一类路径不进主线，也不符合 Apple 小程序伙伴计划条款。

---

## 七、验收方式

当前仓库**没有测试 target**，所有改动只能靠编译 + 手工回归。P0 系列建议同步补一个 `KinterTests` target，先从"令牌三元键隔离""组合规则延时外发""直通模块拦截"三个用例起。
