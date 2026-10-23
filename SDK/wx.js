/*
 * Kinter 小程序 SDK
 * 所有 API 返回 Promise
 * 所有调用走 webkit.messageHandlers.bridge
 */
(function (root) {
  'use strict';

  var seq = 0;
  var pending = {};

  function bridge() {
    var w = root.webkit;
    return (w && w.messageHandlers && w.messageHandlers.bridge) ? w.messageHandlers.bridge : null;
  }

  var BRIDGE_TIMEOUT_MS = 30000;

  function invoke(module, method, params) {
    return new Promise(function (resolve, reject) {
      var h = bridge();
      if (!h) { reject({ code: 'bridge_unavailable', message: 'Native bridge not found' }); return; }
      seq += 1;
      var id = 'cb_' + seq;
      var timer = setTimeout(function () {
        if (pending[id]) {
          delete pending[id];
          reject({ code: 'timeout', message: '原生调用超时: ' + module + '.' + method });
        }
      }, BRIDGE_TIMEOUT_MS);
      pending[id] = { resolve: resolve, reject: reject, timer: timer };
      try {
        h.postMessage({ module: module, method: method, params: params || {}, callbackId: id });
      } catch (e) {
        clearTimeout(timer);
        delete pending[id];
        reject({ code: 'post_message_failed', message: String(e) });
      }
    });
  }

  root.__wxBridgeCallback = function (p) {
    if (!p || !p.callbackId) return;
    var e = pending[p.callbackId];
    if (!e) return;
    if (e.timer) clearTimeout(e.timer);
    delete pending[p.callbackId];
    if (p.ok) {
      e.resolve(p.data);
    } else {
      e.reject(p.error || { code: 'unknown' });
    }
  };

  // ---- 事件系统 ----
  var listeners = {};

  root.__wxEmit = function (p) {
    if (!p || !p.event) return;
    var handlers = listeners[p.event] || [];
    for (var i = 0; i < handlers.length; i++) {
      try { handlers[i](p.data); } catch (err) { console.error('[wx] handler error:', err); }
    }
  };

  function on(event, handler) {
    if (typeof handler !== 'function') return;
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(handler);
  }

  function off(event, handler) {
    if (!listeners[event]) return;
    if (!handler) { delete listeners[event]; return; }
    listeners[event] = listeners[event].filter(function (fn) { return fn !== handler; });
  }

  // ---- wx 对象 ----
  root.wx = {

    // ===== 事件 =====
    on: on,
    off: off,

    // ===== 弹窗 =====
    toast: function (o) { return invoke('popup', 'toast', o); },
    showModal: function (o) { return invoke('popup', 'modal', o); },
    showActionSheet: function (o) { return invoke('popup', 'actionSheet', o); },
    dismissAllPopups: function (o) { return invoke('popup', 'dismissAll', o); },

    // ===== 存储 =====
    setStorage: function (o) { return invoke('storage', 'set', o); },
    getStorage: function (o) { return invoke('storage', 'get', o); },
    removeStorage: function (o) { return invoke('storage', 'remove', o); },

    // ===== 全局数据（运行时，关闭即清空）=====
    globalData: {
      set: function (o) { return invoke('store', 'set', o); },
      get: function (o) { return invoke('store', 'get', o); },
      remove: function (o) { return invoke('store', 'remove', o); },
      clear: function (o) { return invoke('store', 'clear', o); },
      all: function (o) { return invoke('store', 'all', o); }
    },

    // ===== 页面路由 =====
    navigateTo: function (o) { return invoke('router', 'navigateTo', o); },
    redirectTo: function (o) { return invoke('router', 'redirectTo', o); },
    reLaunch: function (o) { return invoke('router', 'reLaunch', o); },
    navigateBack: function (o) { return invoke('router', 'navigateBack', o); },
    getPageStack: function (o) { return invoke('router', 'getStack', o); },

    // ===== 文件 =====
    getDataPath: function (o) { return invoke('files', 'info', o); },
    makeDirectory: function (o) { return invoke('files', 'mkdir', o); },
    listDirectory: function (o) { return invoke('files', 'listDir', o); },
    writeFile: function (o) { return invoke('files', 'write', o); },
    readFile: function (o) { return invoke('files', 'read', o); },
    removeFile: function (o) { return invoke('files', 'remove', o); },
    listFiles: function (o) { return invoke('files', 'list', o); },

    // ===== 网络 =====
    request: function (o) { return invoke('http', 'request', o); },
    upload: function (o) { return invoke('upload', 'upload', o); },

    // ===== WebSocket =====
    wsConnect: function (o) { return invoke('websocket', 'connect', o); },
    wsSend: function (o) { return invoke('websocket', 'send', o); },
    wsClose: function (o) { return invoke('websocket', 'close', o); },
    wsIsOpen: function (o) { return invoke('websocket', 'isOpen', o); },

    // ===== 网络监听 =====
    startNetworkWatch: function (o) { return invoke('networkWatch', 'start', o); },
    stopNetworkWatch: function (o) { return invoke('networkWatch', 'stop', o); },

    // ===== 相机 / 相册 / 麦克风 =====
    chooseImage: function (o) { return invoke('camera', 'chooseImage', o); },
    chooseMedia: function (o) { return invoke('photo', 'chooseMedia', o); },
    startRecord: function (o) { return invoke('microphone', 'start', o); },
    stopRecord: function (o) { return invoke('microphone', 'stop', o); },
    recordVideo: function (o) { return invoke('videoRecord', 'record', o); },
    compressImage: function (o) { return invoke('image', 'compress', o); },
    savePhotoToAlbum: function (o) { return invoke('savePhoto', 'save', o); },

    // ===== 音频 =====
    playAudio: function (o) { return invoke('audio', 'play', o); },
    pauseAudio: function (o) { return invoke('audio', 'pause', o); },
    stopAudio: function (o) { return invoke('audio', 'stop', o); },
    seekAudio: function (o) { return invoke('audio', 'seek', o); },

    // ===== TTS =====
    speak: function (o) { return invoke('tts', 'speak', o); },
    stopSpeaking: function (o) { return invoke('tts', 'stop', o); },

    // ===== 二维码 =====
    scanQR: function (o) { return invoke('qrScan', 'scan', o); },
    generateQR: function (o) { return invoke('qrGenerate', 'generate', o); },

    // ===== OCR =====
    ocr: function (o) { return invoke('ocr', 'recognize', o); },

    // ===== 定位 =====
    getLocation: function (o) { return invoke('location', 'getCurrent', o); },
    startLocationUpdate: function (o) { return invoke('locationWatch', 'start', o); },
    stopLocationUpdate: function (o) { return invoke('locationWatch', 'stop', o); },

    // ===== 设备 =====
    getSystemInfo: function (o) { return invoke('deviceInfo', 'get', o); },
    getBattery: function (o) { return invoke('battery', 'get', o); },
    getNetwork: function (o) { return invoke('network', 'get', o); },
    getMotion: function (o) { return invoke('motion', 'deviceMotion', o); },

    // ===== 剪贴板 =====
    setClipboard: function (o) { return invoke('clipboard', 'set', o); },
    getClipboard: function (o) { return invoke('clipboard', 'get', o); },
    getClipboardImage: function (o) { return invoke('clipboardImage', 'get', o); },
    setClipboardImage: function (o) { return invoke('clipboardImage', 'set', o); },

    // ===== 震动 =====
    vibrateShort: function (o) { return invoke('vibrate', 'short', o); },
    vibrateLong: function (o) { return invoke('vibrate', 'long', o); },

    // ===== 屏幕 =====
    getBrightness: function (o) { return invoke('brightness', 'get', o); },
    setBrightness: function (o) { return invoke('brightness', 'set', o); },
    keepScreenOn: function (o) { return invoke('screenAwake', 'enable', o); },
    keepScreenOff: function (o) { return invoke('screenAwake', 'disable', o); },

    // ===== 通知 =====
    requestNotification: function (o) { return invoke('notification', 'requestPermission', o); },
    scheduleNotification: function (o) { return invoke('notification', 'schedule', o); },

    // ===== 通讯录 / 日历 / 提醒 =====
    getContacts: function (o) { return invoke('contacts', 'getAll', o); },
    addCalendarEvent: function (o) { return invoke('calendar', 'add', o); },
    listCalendarEvents: function (o) { return invoke('calendar', 'list', o); },
    addReminder: function (o) { return invoke('reminder', 'add', o); },

    // ===== 语音识别 =====
    recognizeSpeech: function (o) { return invoke('speech', 'recognizeOnce', o); },

    // ===== 健康 =====
    getStepCount: function (o) { return invoke('health', 'stepCount', o); },

    // ===== 蓝牙 =====
    scanBluetooth: function (o) { return invoke('bluetooth', 'scan', o); },
    scanBluetoothDevices: function (o) { return invoke('bluetoothScan', 'scan', o); },

    // ===== 生物识别 =====
    authenticate: function (o) { return invoke('biometric', 'authenticate', o); },

    // ===== 通信 =====
    makePhoneCall: function (o) { return invoke('communication', 'call', o); },
    sendSMS: function (o) { return invoke('communication', 'sms', o); },
    sendEmail: function (o) { return invoke('communication', 'mail', o); },

    // ===== 分享 / URL =====
    share: function (o) { return invoke('share', 'text', o); },
    openURL: function (o) { return invoke('openURL', 'open', o); },

    // ===== PDF / 打印 =====
    generatePDF: function (o) { return invoke('pdf', 'generate', o); },
    printFile: function (o) { return invoke('print', 'print', o); },

    // ===== 系统搜索（Spotlight）=====
    indexSearchableItem: function (o) { return invoke('spotlight', 'index', o); },
    removeSearchableItem: function (o) { return invoke('spotlight', 'remove', o); },
    removeAllSearchableItems: function (o) { return invoke('spotlight', 'removeAll', o); },

    // ===== 实时活动（Live Activity）=====
    startLiveActivity: function (o) { return invoke('liveActivity', 'start', o); },
    updateLiveActivity: function (o) { return invoke('liveActivity', 'update', o); },
    endLiveActivity: function (o) { return invoke('liveActivity', 'end', o); },
    isLiveActivitySupported: function (o) { return invoke('liveActivity', 'isSupported', o); },
    listLiveActivities: function (o) { return invoke('liveActivity', 'list', o); },
    getLiveActivityState: function (o) { return invoke('liveActivity', 'getState', o); },

    // ===== 账号 =====
    getAccount: function (o) { return invoke('account', 'get', o); },
    isLoggedIn: function (o) { return invoke('account', 'isLoggedIn', o); },

    // ===== 应用间调用 =====
    openApp: function (o) { return invoke('app', 'open', o); },
    canOpenApp: function (o) { return invoke('app', 'canOpen', o); },
    getLaunchParams: function (o) { return invoke('app', 'getLaunchParams', o); }
  };

})(typeof window !== 'undefined' ? window : globalThis);
