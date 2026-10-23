# Kinter 能力清单

每个按钮 = 一次 `模块.方法` 调用，经网关卡点校验后由对应 Provider 调用原生框架。

**链路**：HTML 按钮 → `wx.js` postMessage → `BridgeMessageHandler` → `CapabilityGateway`（manifest / 级别 / 地区 / 权限 / 审计）→ Provider → 原生 API → 回传 JS。

**级别**：L0 无授权 ｜ L1 系统弹窗授权 ｜ L2 需 entitlement

---

## 一、媒体与位置

### 相机（camera.chooseImage，L1）
原生框架：AVFoundation + UIImagePickerController。
原理：先查 `AVCaptureDevice.authorizationStatus`，未决定时 `requestAccess` 弹系统框；授权后以全屏方式呈现系统相机，拍完把 `UIImage` 编码成 JPEG 写入临时目录，返回文件路径给 JS。

### 相册（photo.chooseMedia，L1）
原生框架：PhotosUI + PHPickerViewController。
原理：**PHPicker 不需要相册权限**——它跑在独立进程，用户选完只把选中项回调给 App。所以网关对 photo 直接放行，弹选择器取第一张图落盘，返回临时路径。

### 定位（location.getCurrent，L1）
原生框架：CoreLocation / CLLocationManager。
原理：`.notDetermined` 时调 `requestWhenInUseAuthorization`，授权结果在 `locationManagerDidChangeAuthorization` 里接住，再 `requestLocation()`；拿到坐标后回传经纬度和精度。模拟器返回旧金山默认坐标。

### 语音识别（speech.recognizeOnce，L1）
原生框架：Speech / SFSpeechRecognizer + AVAudioEngine。
原理：先要语音识别授权和麦克风授权，然后在 `inputNode` 上 `installTap` 采集音频流喂给识别请求，识别出文本后回传。**模拟器无输入设备时采样率为 0，会预检并返回 `unsupported`**，不会崩。

---

## 二、设备与系统

### 设备信息（deviceInfo.get，L0）
原生框架：UIKit / UIDevice + UIScreen。
原理：读取机型、系统名、系统版本、`identifierForVendor`、屏幕宽高和缩放倍率，纯本地读取，无授权。

### 电池（battery.get，L0）
原生框架：UIKit / UIDevice。
原理：先开 `isBatteryMonitoringEnabled`，再读 `batteryLevel` 和 `batteryState`（充电/满电/放电/未知）。

### 网络（network.get，L0）
原生框架：Network / NWPathMonitor。
原理：Provider 初始化时启动路径监视器持续记录 `NWPath`；调用时返回当前状态（wifi/cellular/ethernet/offline）和是否计费网络。

### 震动（vibrate.short，L0）
原生框架：UIKit `UIImpactFeedbackGenerator` / AudioToolbox。
原理：短震用触感引擎 `impactOccurred()`，长震用系统振动音效 `kSystemSoundID_Vibrate`。

### 陀螺仪（motion.deviceMotion，L1）
原生框架：CoreMotion / CMMotionManager。
原理：启动设备运动更新（间隔 0.1s），拿到一帧后立刻停止更新，回传 pitch / roll / yaw 三个姿态角。

### 蓝牙（bluetooth.scan，L1）
原生框架：CoreBluetooth / CBCentralManager。
原理：创建 `CBCentralManager` 触发状态回调，返回 poweredOn 或 unauthorized。当前只探测状态，未做设备扫描列表。

### FaceID（biometric.authenticate，L1）
原生框架：LocalAuthentication / LAContext。
原理：先 `canEvaluatePolicy` 检查硬件，支持则弹生物识别验证；**模拟器无硬件，直接返回 `unsupported`**，不会崩。

---

## 三、权限与系统集成

### 通讯录（contacts.getAll，L1）
原生框架：Contacts / CNContactStore。
原理：`requestAccess(for: .contacts)` 授权后，用 `CNContactFetchRequest` 遍历全部联系人，抽取姓名、电话、邮箱返回。

### 日历列表（calendar.list，L1）
原生框架：EventKit / EKEventStore。
原理：`requestFullAccessToEvents` 授权后，用谓词查询最近 30 天的事件，返回标题和开始时间。

### 加提醒（reminder.add，L1）
原生框架：EventKit / EKReminder。
原理：`requestFullAccessToReminders` 授权后，新建 `EKReminder` 挂到默认提醒列表并 `save`。

### 通知授权（notification.requestPermission，L1）
原生框架：UserNotifications / UNUserNotificationCenter。
原理：申请 alert / badge / sound 三项权限，返回用户是否同意。

### 2秒通知（notification.schedule，L1）
原生框架：UserNotifications。
原理：构造 `UNTimeIntervalNotificationTrigger`（2 秒后），包成 `UNNotificationRequest` 提交给系统，到点由系统弹通知。

### 分享（share.text，L0）
原生框架：UIKit / UIActivityViewController。
原理：把文本装进系统分享面板。**iPad 上 popover 必须指定 `sourceView`**，否则呈现动画中抛异常崩溃——统一走 `presentSafely` 扩展设置锚点。

### 开URL（openURL.open，L0）
原生框架：UIKit `UIApplication.shared.open`。
原理：校验 URL 后交给系统，可唤起其他 App 或浏览器。

---

## 四、数据与网络

### 存 / 读（storage.set / get，L0）
原生框架：Foundation / UserDefaults。
原理：键加 `miniapp.storage.` 前缀隔离后写入 UserDefaults，读取时取回原值。

### 写剪贴板 / 读剪贴板（clipboard.set / get，L0）
原生框架：UIKit / UIPasteboard。
原理：直接读写系统剪贴板字符串。主线程执行，返回成功或当前内容。

### 列文件（files.list，L0）
原生框架：Foundation / FileManager。
原理：读 App 沙盒 `Documents` 目录内容。写入/读取同样在此目录，且**校验文件名不含 `..`** 防目录穿越。

### HTTP（http.request，L0）
原生框架：Foundation / URLSession。
原理：用 `URLRequest` 发起请求，支持自定义方法、请求头和请求体，返回状态码和响应文本。截图里 httpbin.org 返回了 200 和完整 JSON。

### 步数（health.stepCount，L2）
原生框架：HealthKit / HKHealthStore。
原理：**需要 `com.apple.developer.healthkit` entitlement**。授权后用 `HKStatisticsQuery` 累加当天步数。缺 entitlement 时 HealthKit 会抛 ObjC 异常，已用 `ObjCExceptionCatcher` 隔离，降级为 `unsupported` 而不是崩溃。

---

## 五、批量自测（runAll）

橙色按钮，非能力。它在页面内依次调用 16 项无交互/低风险能力，每项 3 秒超时，最后汇总成 `✓/✗` 表格显示在结果区。用于一键回归验证网关链路。

---

## 崩溃防护（三条铁律）

1. **同步异常**：网关对每个 Provider 调用包 `ObjCExceptionCatcher`，任何 ObjC 异常降级为 `provider_error`，不拖垮宿主。
2. **异步异常**：网关捕获不到，Provider 内部自行包一层（如 SpeechProvider 的 `installTap`）。
3. **UIKit 呈现**：iPad popover 必须设 `sourceView`，统一用 `presentSafely`。

---

## 六、扩展能力（第二轮 / 第三轮）

### 保存相册（savePhoto.save，L1）
原生框架：Photos / PHPhotoLibrary。
原理：先请求相册读写权限，授权后把 JPEG 数据写入系统相册，返回是否成功。

### 文字转语音（tts.speak，L0）
原生框架：AVFoundation / AVSpeechSynthesizer。
原理：构造 `AVSpeechUtterance`（支持中文语音），加入合成队列播放；可随时 `tts.stop` 停止。

### 扫码（qrScan.scan，L1）
原生框架：AVFoundation / AVCaptureMetadataOutput。
原理：全屏呈现相机并识别二维码/条形码，识别成功即回调返回码内容。

### 生成二维码（qrGenerate.generate，L0）
原生框架：CoreImage / CIFilter.qrGenerator。
原理：把文本编码为二维码 CIImage，转成 UIImage 返回（可带尺寸参数）。

### 文字识别（ocr.recognize，L0）
原生框架：Vision / VNRecognizeTextRequest。
原理：对传入图片执行文本识别，返回识别文本与置信度。支持中文。

### 音频播放（audio.play，L0）
原生框架：AVFoundation / AVAudioPlayer。
原理：播放本地音频文件，支持播放/暂停/停止/跳转。

### 音乐播放（music.play，L0）
原生框架：AVFoundation / AVPlayer。
原理：播放本地文件或 http(s) 远程音乐，支持暂停/恢复/停止/跳转、循环（`loop`）、音量（`volume`）与完整状态查询（`getState`）。宿主已声明 `UIBackgroundModes=audio`，锁屏/退后台后音乐继续播放。

### 持续定位（locationWatch.start，L1）
原生框架：CoreLocation / CLLocationManager。
原理：请求定位权限后启动 `startUpdatingLocation`，持续把坐标通过事件通道推送给 JS（`wx.on` 订阅）。

### 蓝牙扫描（bluetoothScan.scan，L1）
原生框架：CoreBluetooth / CBCentralManager。
原理：`scanForPeripherals` 扫描附近设备，把发现的设备列表（名称、UUID、RSSI）回调返回。

### 通信（communication.call / sms / mail，L0）
原生框架：UIKit / UIApplication。
原理：用 `tel:`、`sms:`、`mailto:` URL 唤起系统拨号/短信/邮件界面。

### 亮度（brightness.get / set，L0）
原生框架：UIKit / UIScreen。
原理：读改 `UIScreen.main.brightness`，返回 0~1 浮点。

### 屏幕常亮（screenAwake.enable / disable，L0）
原生框架：UIKit / UIApplication。
原理：切换 `isIdleTimerDisabled`，阻止自动息屏。

### WebSocket（websocket.connect / send / close，L0）
原生框架：Network / NWConnection（或 URLSessionWebSocketTask）。
原理：建立长连接，收发文本消息；连接状态与消息通过事件通道推送给 JS。

### 图片压缩（image.compress，L0）
原生框架：UIKit / UIGraphicsImageRenderer。
原理：按比例缩放并设置 JPEG 压缩质量，输出压缩后图片路径。

### 视频录制（videoRecord.record，L1）
原生框架：AVFoundation / UIImagePickerController（video 类型）。
原理：全屏呈现系统相机录像，完成后返回视频文件路径。

### 文件上传（upload.upload，L0）
原生框架：Foundation / URLSession。
原理：以 multipart/form-data 上传本地文件到指定 URL，返回状态码与响应。

### 网络监听（networkWatch.start / stop，L0）
原生框架：Network / NWPathMonitor。
原理：持续监视网络路径，变化时通过事件通道推送（类型、计费状态）。

### 剪贴板图片（clipboardImage.get / set，L0）
原生框架：UIKit / UIPasteboard。
原理：读写系统剪贴板中的图片数据。

### PDF 生成（pdf.generate，L0）
原生框架：UIKit / UIGraphicsPDFRenderer。
原理：把 HTML 或视图渲染成 PDF 文件，返回路径。

### 打印（print.print，L0）
原生框架：UIKit / UIPrintInteractionController。
原理：调起 AirPrint 面板打印 PDF/图片。

### 账号信息（account.get / isLoggedIn，L0）
原生框架：KinterAuthManager。
原理：只读返回当前登录用户的公开信息（id、用户名、显示名），**不返回 token**；可在设置里全局禁止小程序读取。

### 系统搜索（spotlight.index / remove，L0）
原生框架：CoreSpotlight / CSSearchableIndex。
原理：把小程序内容索引到系统 Spotlight，点击通过深链回小程序；按 appId 隔离索引域。

### 实时活动（liveActivity.start / update / end，L2）
原生框架：ActivityKit。
原理：需要 Widget Extension（KinterActivityWidget）与 iOS 16.1+；启动锁屏/灵动岛活动，支持更新进度、深链与过期时间。模拟器不可用。
