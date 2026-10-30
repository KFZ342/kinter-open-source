# 常见问题排查

## 错误码速查

| code | 含义 | 排查方向 |
|---|---|---|
| `capability_not_declared` | 能力未在 manifest 声明 | 检查 manifest.json 的 capabilities 字段 |
| `level_denied` | 级别不满足 | 声明的 level 与网关注册不一致 |
| `permission_denied` | 系统权限被拒 | 引导用户 `wx.openSetting()` 去设置开启 |
| `not_available` | 设备不支持 | 模拟器常见，换真机测 |
| `invalid_params` | 参数非法 | 对照 API 文档检查字段名 |
| `method_not_found` | 方法不存在 | 拼写错误，或模块下没这个方法 |
| `provider_error` | 执行出错 | 看宿主日志面板的详细错误 |
| `timeout` | 30s 超时 | 原生回调未触发，检查权限或设备状态 |
| `bridge_unavailable` | 原生桥不存在 | 页面不在宿主内打开（用普通浏览器了） |

## 白屏排查

1. 打开宿主日志面板，找 `[Bridge]` 开头的日志
2. 检查 manifest.json 是否合法（JSON 语法、必填字段）
3. 检查 index.html 是否存在且路径正确
4. 看有没有 `console.error` 输出
5. 确认 pages 数组与文件路径对应

## 权限被拒排查

```js
// 先查状态
const { authSetting } = await wx.getSetting();
console.log(authSetting['scope.camera']);

// 未授权则申请
await wx.authorize({ permission: 'scope.camera' });

// 被拒后引导去设置
await wx.openSetting();
```

**不要把授权框放在页面加载时自动弹出**，要在用户明确操作功能时申请。

## 能力调不通排查

1. manifest 是否声明？→ `capability_not_declared`
2. 级别是否一致？→ `level_denied`
3. 用户是否在应用设置里禁用了？→ `permission_denied`
4. 系统权限是否授予？→ `permission_denied`
5. 设备是否支持？→ `not_available`
6. 看审计日志：哪个模块、什么方法、耗时多少

## 小程序安装失败

- ZIP 结构：manifest.json 必须在根目录或一层子目录
- appId 格式：只能字母数字._-，不能有中文
- 版本号：建议语义化 `1.0.0`
- 大小：上限 50MB
- 路径：不能含 `..`、不能绝对路径

## AI 生成失败

| 现象 | 原因 | 处理 |
|---|---|---|
| 「模型输出中找不到 JSON」 | 模型没用纯 JSON 输出 | 重试，或在设置里换模型 |
| 「JSON 解析失败」 | 模型输出被截断 | 降低复杂度，分批生成 |
| 「缺少 index.html」 | 模型漏了必需文件 | 重试，明确说「必须包含 index.html」 |
| 「非法路径」 | 模型生成了 `../` 路径 | 安全拦截，重试 |
| 能力被剔除 | 模型编造了不存在的能力 ID | 提示词里已有完整清单，重试 |

## badQuery 返回 degraded

- `code:-1`：当前系统无 containermanager 符号（模拟器正常现象）
- `code:-3`：路径超出可查询范围，换可达区域
- `code:-4`：内核拒绝，可能系统已修复
- 返回 `blocked:true`：命中安全护栏，是主动拦截不是失败

## 桥接超时

- 检查能力是否有权限（未授权时某些 Provider 不会回调）
- 看宿主日志有没有 `[Bridge]` 调用记录
- 模拟器上相机/麦克风等会立即返回 `unsupported`，不会超时
- 如果是自定义 Provider，确认 completion 一定被调用

## 日志在哪看

1. **宿主内**：AI 管家聊天页有工具执行记录；小程序运行时点右上角可看 console 日志
2. **Xcode**：运行宿主后看 Console，过滤 `[Bridge]` 或进程名
3. **模拟器日志**：`xcrun simctl spawn booted log stream --predicate 'process == "Kinter"'`
