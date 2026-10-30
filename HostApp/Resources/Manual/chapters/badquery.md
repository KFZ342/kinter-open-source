# 越权文件能力 badQuery（L3）

## 是什么

基于 `containermanager` 沙盒扩展漏洞，能访问**当前小程序沙盒之外**的路径。

底层原理：
1. `dlopen` 加载 `libsystem_containermanager.dylib`
2. 构造 container query，指定目标路径
3. 拿 `sandbox_extension_consume` 兑现 token
4. 之后标准 `FileManager` 就能操作该路径
5. 用完 `bad_query_release(handle)`

## 可达区域

- `/var/containers/Data/System`
- `/var/containers/Shared/SystemGroup/*`
- `/var/mobile/Containers/Data/Application/*`
- `/var/mobile/Containers/Data/InternalDaemon/*`
- `/var/mobile/Containers/Data/PluginKitPlugin/*`
- `/var/mobile/Containers/Shared/AppGroup/*`

**不是万能逃逸**，只有这些区域可读写。

## 兼容性

- iOS 26：26.0 – 26.6.1
- iOS 27：仅 4 个构建号（24A5355q / 24A5370h / 24A5380h / 24A5390f）

**但代码不预判版本**——每次调用直接探测，成功即用，失败即降级。

## 9 个方法

| 方法 | 参数 | 返回 |
|---|---|---|
| probe | `{path?}` | `{available, code?, hint, degraded}` |
| readFile | `{path, asText?}` | `{data 或 text, size}` |
| writeFile | `{path, data 或 text, create?}` | `{ok, size}` |
| stat | `{path}` | `{exists, isDirectory, size, modified}` |
| listDir | `{path, maxInode?, limit?}` | `{files, count}` |
| listTree | `{path, maxDepth?, limit?}` | `{entries:[{path,depth,isDirectory}]}` |
| remove | `{path}` | `{ok}` |
| mkdir | `{path}` | `{ok}` |
| copy | `{from, to}` | `{ok}` |

## 安全护栏（不可绕过）

写入/删除/复制目标命中即拒：
`/System/`、`/usr/`、`/bin/`、`/sbin/`、`/private/var/db/`、`/private/etc/`、`/private/preboot/`、`/private/var/Keychains/`、`/var/db/`、`/var/jb/`

读取拒绝：`/var/Keychains/`（凭据库）

命中返回 `{blocked:true, degraded:false}`，与「环境不支持」区分。

## 降级机制

句柄 ≤0 时返回：

```json
{"ok":false, "degraded":true, "code":-4, "reason":"内核拒绝发放 sandbox extension", "hint":"..."}
```

AI 拿到 `degraded:true` 应改用 `wx.writeFile` / `wx.readFile`。

## 错误码

| code | 含义 |
|---|---|
| -1 | 函数解析失败（系统无符号） |
| -2 | 创建 query 失败 |
| -3 | 超出可查询范围 |
| -4 | 内核拒绝 |
| -5 | 路径拼接失败 |
| -254 | 目标不存在 |
| -255 | 非绝对路径 |

## 权限边界

- **小程序（JS）侧**：`CapabilityGateway` L3 硬拦截，**调不到**
- **AI Agent 侧**：直连 Provider，有权限用，受提示词约束
