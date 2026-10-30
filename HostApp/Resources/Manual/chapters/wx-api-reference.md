# wx API 分模块速查

## 弹窗（popup，L0）
`wx.toast({text})` / `wx.showModal({title,content})` / `wx.showActionSheet({items})` / `wx.dismissAllPopups()`

## 存储（storage，L0 持久化）
`wx.setStorage({key,data})` / `wx.getStorage({key})` / `wx.removeStorage({key})`

## 全局数据（store，会话级）
`wx.globalData.set/get/remove/clear/all`

## 文件（files，L0，按 appId 隔离）
`wx.getDataPath()` / `wx.makeDirectory({name})` / `wx.listDirectory({name?})` / `wx.writeFile({name,data})` / `wx.readFile({name})` / `wx.removeFile({name})`

## 路由（router，无权限）
`wx.navigateTo({url})` / `redirectTo` / `reLaunch` / `navigateBack({delta})` / `getPageStack()`

## 网络（http/upload，L0）
`wx.request({url,method,headers,body})` — 响应上限 10MB，超时默认 30s（上限 60s）
`wx.upload({url,filePath,field,fields})` — multipart 上传

## WebSocket（L0）
`wx.wsConnect({url})` / `wsSend({data})` / `wsClose({code})` / `wsIsOpen()`

## 网络监听（L0）
`wx.startNetworkWatch()` / `stopNetworkWatch()`

## 相机/相册（L1）
`wx.chooseImage({count,sourceType})` — 相机/相册选图
`wx.chooseMedia({count})` — 相册多选（PHPicker 免权限）
`wx.savePhotoToAlbum({path})` — 保存到相册
`wx.compressImage({path,quality})` — 压缩（L0）

## 录音/录像（L1）
`wx.startRecord()` / `stopRecord()` / `wx.recordVideo({maxDuration})`

## 音频（audio，L0）
`wx.playAudio({path})` / `pauseAudio()` / `stopAudio()` / `seekAudio({position})`

## 音乐（music，L0，AVPlayer）
`wx.playMusic({path,loop,volume,position})` / `pauseMusic()` / `resumeMusic()` / `stopMusic()` / `seekMusic({position})` / `getMusicState()` / `setMusicVolume({volume})`
宿主已声明 `UIBackgroundModes=audio`，支持后台播放。

## TTS（tts，L0）
`wx.speak({text,lang,rate})` / `wx.stopSpeaking()`

## 二维码
`wx.scanQR()`（L1）/ `wx.generateQR({text,size})`（L0）

## OCR（L0）
`wx.ocr({path})` — Vision 框架，支持中文

## 定位
`wx.getLocation()`（L1）/ `wx.startLocationUpdate()` / `stopLocationUpdate()`

## 设备
`wx.getSystemInfo()`（L0）/ `wx.getBattery()`（L0）/ `wx.getNetwork()`（L0）/ `wx.getMotion()`（L1）

## 剪贴板（L0）
`wx.setClipboard({text})` / `getClipboard()` / `getClipboardImage()` / `setClipboardImage({path})`

## 震动/屏幕（L0）
`wx.vibrateShort()` / `vibrateLong()`
`wx.getBrightness()` / `setBrightness({value})` / `keepScreenOn()` / `keepScreenOff()`

## 通知（L1）
`wx.requestNotification()` / `wx.scheduleNotification({title,body,time})`

## 通讯录/日历/提醒（L1）
`wx.getContacts()` / `wx.addCalendarEvent({title,startDate})` / `wx.listCalendarEvents({startDate,endDate})` / `wx.addReminder({title,dueDate})`

## 语音识别（L1）
`wx.recognizeSpeech({lang})`

## 健康（L2，需 entitlement）
`wx.getStepCount()` — 缺 entitlement 时降级 `unsupported`

## 蓝牙（L1）
`wx.scanBluetooth({timeout})` / `wx.scanBluetoothDevices({timeout})`

## 生物识别（L1）
`wx.authenticate({reason})` — Face ID / Touch ID

## 通信（L0）
`wx.makePhoneCall({phone})` / `sendSMS({phone,body})` / `sendEmail({to,subject,body})`

## 分享/URL（L0）
`wx.share({text})`
`wx.openURL({url})` — 支持自定义 scheme，`file://`/`javascript://` 等被硬禁
`wx.canOpenURL({url})` — 预检

## PDF/打印（L0）
`wx.generatePDF({path})` / `wx.printFile({path})`

## 系统搜索（L0）
`wx.indexSearchableItem({title,content,url})` / `removeSearchableItem({id})` / `removeAllSearchableItems()`

## 实时活动（L2，需 Widget Extension + iOS 16.1+）
`wx.startLiveActivity({title,progress})` / `updateLiveActivity` / `endLiveActivity` / `isLiveActivitySupported()`

## 账号（L0，只读）
`wx.getAccount()` / `wx.isLoggedIn()` — 不返回 token

## 权限管理（permission）
`wx.getPermissionStatus({permission})` / `getSetting()` / `authorize({permission})` / `openSetting()`
20 类 scope：camera/record/userLocation/album/writePhotosAlbum/addressBook/calendar/reminders/notification/bluetooth/werun/speech/faceId/health/tracking/mediaLibrary/homeKit/localNetwork/nfc/nearby

## 应用间调用（app）
`wx.openApp({appId,params})` / `canOpenApp({appId})` / `getLaunchParams()`
