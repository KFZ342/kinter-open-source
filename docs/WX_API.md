# wx API 参考

`SDK/wx.js` 提供全局 `wx` 对象。**所有 API 返回 Promise**，通过 `webkit.messageHandlers.bridge` 与宿主桥接。

## 通用约定

### 调用形态

```js
wx.chooseImage({ count: 1 })
  .then(res => { /* res 为原生返回 */ })
  .catch(err => console.error(err.code, err.message))
```

### 超时

所有桥接调用统一 **30 秒超时**。原生未回调时 Promise 以 `{code:'timeout'}` 拒绝，不会永久挂起。

### 错误码

| code | 含义 |
|---|---|
| `capability_not_declared` | 该能力未在 manifest.json 声明 |
| `level_denied` | 能力级别（L0/L1/L2）不满足 |
| `region_unavailable` | 当前地区不可用 |
| `permission_denied` | 系统权限被拒绝（或未授权） |
| `not_available` | 设备/系统不支持该能力 |
| `invalid_params` | 参数缺失或非法 |
| `method_not_found` | 模块下没有该方法 |
| `provider_error` | Provider 执行出错 |
| `timeout` | 桥接 30s 超时 |
| `bridge_unavailable` | 原生桥不存在（页面在普通浏览器打开） |

### manifest 声明

每个能力都需要在 `manifest.json` 里声明才会放行（未声明调用直接 `capability_not_declared`）：

```json
{
  "capabilities": {
    "camera": { "level": "L1" },
    "files":  { "level": "L0" }
  }
}
```

声明名 = 下表「模块」列；级别须与下表一致（L0 无授权 / L1 系统弹窗 / L2 需 entitlement）。

## 事件系统

```js
const h = data => console.log(data);
wx.on('websocket.message', h);   // 订阅
wx.off('websocket.message', h);  // 退订（不传 handler 则清空该事件全部）
```

| 事件 | 数据 | 来源 |
|---|---|---|
| `websocket.open` | `{protocol}` | wsConnect 成功 |
| `websocket.message` | `{data}` 或 `{data, binary:true}` | 收到消息 |
| `websocket.close` | `{code}` | 连接关闭 |
| `websocket.error` | `{message}` | 连接出错 |
| `network.change` | `{type, ...}` | 网络状态变化 |

## API 清单

### 弹窗（模块 `popup`，无权限）

| API | 说明 |
|---|---|
| `wx.toast({message})` | 轻提示 |
| `wx.showModal({title, message, okText?, cancelText?})` | 确认框，返回用户选择 |
| `wx.showActionSheet({title?, items:[...]})` | 操作列表，返回选中项 |
| `wx.dismissAllPopups()` | 关闭全部宿主弹窗 |

### 本地存储（`storage`，L0，持久化）

| API | 说明 |
|---|---|
| `wx.setStorage({key, value})` | 写（值需 JSON 可序列化） |
| `wx.getStorage({key})` | 读 |
| `wx.removeStorage({key})` | 删 |

### 全局数据（`store`，无权限，会话级，页面间共享、关闭清空）

| API | 说明 |
|---|---|
| `wx.globalData.set({key, value})` | 写 |
| `wx.globalData.get({key})` | 读 |
| `wx.globalData.remove({key})` | 删 |
| `wx.globalData.clear()` | 清空 |
| `wx.globalData.all()` | 全部 |

### 页面路由（`router`，无权限）

| API | 说明 |
|---|---|
| `wx.navigateTo({path, params?})` | 入栈跳转（栈上限 10） |
| `wx.redirectTo({path, params?})` | 替换当前页 |
| `wx.reLaunch({path, params?})` | 清栈重开 |
| `wx.navigateBack({delta?})` | 返回（默认 1） |
| `wx.getPageStack()` | 当前页面栈 |

### 文件（`files`，L0，按 appId 隔离沙盒）

| API | 说明 |
|---|---|
| `wx.getDataPath()` | 数据根目录 |
| `wx.makeDirectory({path})` | 建目录 |
| `wx.listDirectory({path})` | 列目录 |
| `wx.writeFile({path, data})` | 写文件 |
| `wx.readFile({path})` | 读文件 |
| `wx.removeFile({path})` | 删文件/目录 |
| `wx.listFiles({path?})` | 递归列出文件 |

### 网络（`http` / `upload`，L0）

| API | 说明 |
|---|---|
| `wx.request({url, method?, headers?, body?, timeout?})` | HTTP 请求；响应体上限 10MB，超时默认 30s（上限 60s） |
| `wx.upload({url, filePath, name?, headers?})` | multipart 上传文件 |

### WebSocket（`websocket`，L0）

| API | 说明 |
|---|---|
| `wx.wsConnect({url, protocols?})` | 建立连接（成功触发 `websocket.open`） |
| `wx.wsSend({data})` | 发送文本 |
| `wx.wsClose({code?})` | 关闭 |
| `wx.wsIsOpen()` | 是否已连接 |

### 网络监听（`networkWatch`，L0）

| API | 说明 |
|---|---|
| `wx.startNetworkWatch()` | 开始监听（变化触发 `network.change`） |
| `wx.stopNetworkWatch()` | 停止 |

### 相机 / 相册 / 媒体（L1 为主）

| API | 模块 | 级别 | 说明 |
|---|---|---|---|
| `wx.chooseImage({count?, sourceType?})` | camera | L1 | 相机/相册选图，返回图片路径 |
| `wx.chooseMedia({count?})` | photo | L1 | 相册多选 |
| `wx.startRecord()` / `wx.stopRecord()` | microphone | L1 | 录音，stop 返回音频路径 |
| `wx.recordVideo({maxDuration?})` | videoRecord | L1 | 录像 |
| `wx.compressImage({path, quality?})` | image | L0 | 图片压缩 |
| `wx.savePhotoToAlbum({path})` | savePhoto | L1 | 保存到相册 |

### 音频（`audio`，L0）

`wx.playAudio({path})` / `wx.pauseAudio()` / `wx.stopAudio()` / `wx.seekAudio({position})`

### 音乐（`music`，L0，AVPlayer）

本地文件或 http(s) 远程 URL，支持后台播放（宿主已声明 `UIBackgroundModes=audio`）：

| API | 说明 |
|---|---|
| `wx.playMusic({path, loop?, volume?, position?})` | 播放，path 为本地路径或 URL；loop 循环；volume 0-1；position 起始秒 |
| `wx.pauseMusic()` | 暂停（保留进度） |
| `wx.resumeMusic()` | 恢复 |
| `wx.stopMusic()` | 停止并释放 |
| `wx.seekMusic({position})` | 跳转（秒） |
| `wx.getMusicState()` | 返回 `{playing, paused, duration, position, volume, loop}` |
| `wx.setMusicVolume({volume})` | 音量 0-1 |

### TTS（`tts`，L0）

`wx.speak({text, rate?})` / `wx.stopSpeaking()`

### 二维码（`qrScan` L1 / `qrGenerate` L0）

`wx.scanQR()` 扫码；`wx.generateQR({text, size?})` 生成二维码图片

### OCR（`ocr`，L0）

`wx.ocr({path})` 图片文字识别，返回文本与置信度

### 定位（`location` L1 / `locationWatch` L1）

| API | 说明 |
|---|---|
| `wx.getLocation()` | 单次定位（经纬度） |
| `wx.startLocationUpdate()` | 启动持续定位（坐标累积） |
| `wx.stopLocationUpdate()` | 停止并取回累积坐标 |

### 设备（L0/L1）

`wx.getSystemInfo()`（deviceInfo L0）、`wx.getBattery()`（battery L0）、`wx.getNetwork()`（network L0）、`wx.getMotion()`（motion L1，陀螺仪/加速度）

### 剪贴板（L0）

`wx.setClipboard({text})` / `wx.getClipboard()` / `wx.getClipboardImage()` / `wx.setClipboardImage({path})`

### 震动（`vibrate`，L0）

`wx.vibrateShort()` / `wx.vibrateLong()`

### 屏幕（`brightness` / `screenAwake`，L0）

`wx.getBrightness()` / `wx.setBrightness({value})` / `wx.keepScreenOn()` / `wx.keepScreenOff()`

### 通知（`notification`，L1）

`wx.requestNotification()` 请求通知权限；`wx.scheduleNotification({title, body?, time?, id?})` 本地通知

### 通讯录 / 日历 / 提醒（L1）

`wx.getContacts()`、`wx.addCalendarEvent({title, startDate, endDate?})`、`wx.listCalendarEvents({startDate, endDate})`、`wx.addReminder({title, dueDate?})`

### 语音识别（`speech`，L1）

`wx.recognizeSpeech({lang?})` 一次语音识别，返回文本

### 健康（`health`，L2，需 entitlement）

`wx.getStepCount()` 当天步数

### 蓝牙（L1）

`wx.scanBluetooth({timeout?})`（bluetooth）、`wx.scanBluetoothDevices({timeout?})`（bluetoothScan，含 RSSI）

### 生物识别（`biometric`，L1）

`wx.authenticate({reason})` Face ID / Touch ID

### 通信（`communication`，L0）

`wx.makePhoneCall({phone})` / `wx.sendSMS({phone, body?})` / `wx.sendEmail({to?, subject?, body?})`

### 分享 / 打开链接（L0）

`wx.share({text})` 系统分享；`wx.openURL({url})` 打开链接

### PDF / 打印（L0）

`wx.generatePDF({html?})` 生成 PDF；`wx.printFile({path})` AirPrint

### 系统搜索（`spotlight`，L0）

`wx.indexSearchableItem({title, content?, url?})` / `wx.removeSearchableItem({id})` / `wx.removeAllSearchableItems()`

### 实时活动（`liveActivity`，L2，需 Widget Extension + iOS 16.1+）

`wx.startLiveActivity({title, body?, progress?, deepLink?})` / `wx.updateLiveActivity({id?, ...})` / `wx.endLiveActivity({id?})` / `wx.isLiveActivitySupported()` / `wx.listLiveActivities()` / `wx.getLiveActivityState({id})`

### 账号（`account`，L0，只读）

`wx.getAccount()` 当前登录用户公开信息（无 token）；`wx.isLoggedIn()` 是否登录

### 应用间调用（`app`，无权限）

`wx.openApp({appId, params?})` 打开另一个小程序；`wx.canOpenApp({appId})` 是否已安装；`wx.getLaunchParams()` 启动参数

## 说明

- 参数名以各 Provider 实现为准，上表为常用形态；能力细节见 [docs/CAPABILITIES.md](CAPABILITIES.md)
- 同一模块下未列出的方法（如 `wx.foo()`）会返回 `method_not_found`
- 页面脚本可通过 `window.__wxBridgeCallback` / `window.__wxEmit` 直接对接底层，但不建议（wx.* 已封装）
