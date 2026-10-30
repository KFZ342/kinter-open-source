# 能力网关与权限分级

## 能力级别

| 级别 | 含义 | 需要 |
|---|---|---|
| L0 | 无授权 | 无 |
| L1 | 系统弹窗授权 | 用户点击同意 |
| L2 | 需 entitlement | 证书/Info.plist 配置 |
| L3 | 最高危 | 网关直接拦截，不开放给小程序 |

## 五道安检（CapabilityGateway.invoke）

1. **manifest 检查**：无 manifest → `unsupported("no manifest loaded")`
2. **声明检查**：`manifest.declares(module)` 为假 → `capability_not_declared`
3. **用户禁用**：`disabledCapabilities` 命中 → `permission_denied`
4. **级别检查**：`level == .l3` → `unsupported`（硬拦截）
5. **区域 + 系统权限**：`RegionSensitiveProvider.isAvailableInCurrentRegion()`、`PermissionPolicy.check`

每道都通过后，用 `ObjCExceptionCatcher` 包住 Provider 调用——单个能力崩溃不拖垮宿主。

## manifest 声明示例

```json
{
  "appId": "com.example.hello",
  "version": "1.0.0",
  "name": "示例应用",
  "pages": ["index"],
  "capabilities": {
    "camera": { "level": "L1" },
    "files":  { "level": "L0" },
    "deviceInfo": { "level": "L0" }
  }
}
```

**未声明的能力调用一律返回 `capability_not_declared`。**

## 每会话独立实例

每个小程序窗口持有自己的 `CapabilityGateway`：
- `providers = registry.makeFreshProviders()`
- 各自的 `launchParams`、`currentManifest`、`disabledCapabilities`

多任务并行时不会互相覆盖权限状态。

## 审计日志

每次 invoke 都记录到 `AuditLog`：模块、方法、结果、耗时（ms）。便于排查哪个小程序在何时调了什么。

## 用户手动禁用

用户在「应用设置」里关掉某能力后，`disabledCapabilities` 会被注入，该能力的调用直接返回 `permission_denied`，不再走系统权限流程。

## L3 与越权能力

L3 是硬拦截层。`badQuery`（沙盒扩展）注册为 L3，**小程序（JS）侧无法调用**。只有宿主内部的 AI Agent 通过独立实例访问，见「越权文件能力」章节。
