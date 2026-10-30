# wx API 通用约定

## 调用形态

所有 API 返回 **Promise**：

```js
wx.chooseImage({ count: 1 })
  .then(res => console.log(res.tempFilePaths))
  .catch(err => console.error(err.code, err.message))
```

推荐 async/await + try/catch。

## 超时

统一 **30 秒超时**，超时以 `{code:'timeout'}` 拒绝。
**例外**：`showModal` / `showActionSheet` 等待用户操作，不设超时。

## 错误码表

| code | 含义 |
|---|---|
| `capability_not_declared` | 该能力未在 manifest.json 声明 |
| `level_denied` | 能力级别不满足 |
| `region_unavailable` | 当前地区不可用 |
| `permission_denied` | 系统权限被拒或用户禁用 |
| `not_available` | 设备/系统不支持 |
| `invalid_params` | 参数缺失或非法 |
| `method_not_found` | 模块下没有该方法 |
| `provider_error` | Provider 执行出错 |
| `timeout` | 桥接 30s 超时 |
| `bridge_unavailable` | 原生桥不存在（在普通浏览器打开） |

## 事件系统

```js
const h = data => console.log(data);
wx.on('websocket.message', h);
wx.off('websocket.message', h);
```

| 事件 | 数据 | 来源 |
|---|---|---|
| `websocket.open` | `{protocol}` | wsConnect 成功 |
| `websocket.message` | `{data}` 或 `{data, binary:true}` | 收到消息 |
| `websocket.close` | `{code}` | 连接关闭 |
| `websocket.error` | `{message}` | 连接出错 |
| `network.change` | `{status, expensive}` | 网络变化 |

## manifest 声明规则

```json
{
  "capabilities": {
    "camera": { "level": "L1" },
    "files":  { "level": "L0" }
  }
}
```

声明名 = 模块名，级别须与网关注册表一致。未声明直接 `capability_not_declared`。
