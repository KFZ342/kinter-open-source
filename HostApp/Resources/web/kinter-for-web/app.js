/* Kinter for Web — 纯浏览器宿主
 * 不依赖 Kinter iOS 宿主、不请求任何后端接口。
 * 应用包 / 应用数据 / 虚拟文件全部保存在 LocalStorage。
 */
(function () {
  'use strict';

  var LS = {
    index: 'kfw.index.v1',
    appPrefix: 'kfw.app.',
    dataPrefix: 'kfw.data.',
    fsPrefix: 'kfw.fs.',
    settings: 'kfw.settings.v1'
  };
  var CAPACITY = 5 * 1024 * 1024;
  var MAX_APP_BYTES = 4.2 * 1024 * 1024;
  var BASE_URL = new URL('.', location.href).href;
  var FRAME_LOGGER = '(function(){' +
    'if(document.documentElement.getAttribute("data-kfw-logger")==="1")return;' +
    'document.documentElement.setAttribute("data-kfw-logger","1");' +
    'var p=window.parent;' +
    'function s(v){try{return typeof v==="string"?v:(v instanceof Error?(v.stack||v.message):JSON.stringify(v));}catch(e){return String(v);}}' +
    'function send(l,a){try{p.postMessage({type:"kfw-log",level:l,message:Array.prototype.map.call(a,s).join(" ")}, "*");}catch(e){}}' +
    '["log","info","warn","error"].forEach(function(k){var o=console[k];console[k]=function(){send(k,arguments);try{o.apply(console,arguments);}catch(e){}};});' +
    'window.addEventListener("error",function(e){send("error",[e.message+" @ "+(e.filename||"")+":"+(e.lineno||0)]);});' +
    'window.addEventListener("unhandledrejection",function(e){send("error",["Unhandled: "+((e.reason&&e.reason.message)||e.reason)]);});' +
    '})();';

  var CAPABILITIES = [
    { id: 'camera', name: '相机' },
    { id: 'photo', name: '相册' },
    { id: 'microphone', name: '麦克风' },
    { id: 'location', name: '定位' },
    { id: 'clipboard', name: '剪贴板' },
    { id: 'files', name: '文件' },
    { id: 'storage', name: '存储' },
    { id: 'http', name: '网络请求' },
    { id: 'websocket', name: 'WebSocket' },
    { id: 'notification', name: '通知' },
    { id: 'tts', name: '语音合成' },
    { id: 'audio', name: '音频' },
    { id: 'music', name: '音乐' },
    { id: 'share', name: '分享' },
    { id: 'deviceInfo', name: '设备信息' },
    { id: 'battery', name: '电池' },
    { id: 'network', name: '网络状态' },
    { id: 'screenAwake', name: '常亮' },
    { id: 'router', name: '页面路由' },
    { id: 'popup', name: '原生弹窗' }
  ];
  var CAP_NAMES = {};
  CAPABILITIES.forEach(function (c) { CAP_NAMES[c.id] = c.name; });

  var PERMISSIONS = [
    { id: 'camera', name: '摄像头', desc: '拍照 / chooseImage', query: 'camera', icon: 'camera' },
    { id: 'microphone', name: '麦克风', desc: '录音 / startRecord', query: 'microphone', icon: 'mic' },
    { id: 'geolocation', name: '定位', desc: 'getLocation / 位置监听', query: 'geolocation', icon: 'pin' },
    { id: 'notifications', name: '通知', desc: '本地通知', query: 'notifications', icon: 'bell' },
    { id: 'clipboard-read', name: '剪贴板读取', desc: 'getClipboard', query: 'clipboard-read', icon: 'clip' },
    { id: 'persistent-storage', name: '持久存储', desc: 'LocalStorage 容量', query: 'persistent-storage', icon: 'drive' }
  ];

  var PALETTE = ['#0ea5a0', '#2f7fd1', '#e0873c', '#4c9e63', '#c9544d', '#3d8f9a', '#b5892f'];

  var state = {
    apps: [],
    sort: 'recent',
    query: '',
    diskPath: '/',
    diskQuery: '',
    diskEntries: [],
    preview: null,
    running: null,
    records: {},
    settings: {},
    modals: [],
    recorders: {},
    audio: {},
    music: {},
    watch: {},
    socket: null,
    blobUrls: [],
    eventsQueued: [],
    logs: [],
    unreadLogs: 0,
    consoleOpen: false
  };

  var el = {};

  /* ---------------- 基础工具 ---------------- */

  function $(id) { return document.getElementById(id); }
  function escapeHTML(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function safeIcon(icon) {
    return typeof icon === 'string' && /^data:image\//.test(icon) ? icon : '';
  }
  function lsAvailable() {
    try {
      if (typeof localStorage === 'undefined') return false;
      localStorage.getItem('__kfw_probe__');
      return true;
    } catch (e) { return false; }
  }
  function lsGet(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }
  function lsSet(key, value) {
    try {
      localStorage.setItem(key, value);
      return true;
    } catch (e) {
      var quota = e && (e.name === 'QuotaExceededError' || e.name === 'NS_ERROR_DOM_QUOTA_REACHED');
      var err = new Error(quota ? 'LocalStorage 空间不足，写入失败' : ('LocalStorage 不可用：' + (e && e.message || e)));
      err.code = quota ? 'quota_exceeded' : 'storage_unavailable';
      throw err;
    }
  }
  function lsRemove(key) {
    try { localStorage.removeItem(key); } catch (e) {}
  }
  function lsKeys() {
    try {
      var out = [];
      for (var i = 0; i < localStorage.length; i++) out.push(localStorage.key(i));
      return out;
    } catch (e) { return []; }
  }
  function lsCount() {
    try { return localStorage.length; } catch (e) { return 0; }
  }
  function readJSON(key, fallback) {
    try {
      var raw = lsGet(key);
      if (!raw) return fallback;
      return JSON.parse(raw);
    } catch (e) { return fallback; }
  }
  function writeJSON(key, value) {
    lsSet(key, JSON.stringify(value));
  }
  async function probeCapacity() {
    try {
      if (navigator.storage && navigator.storage.estimate) {
        var est = await navigator.storage.estimate();
        if (est && est.quota && est.quota > 0) return Math.min(CAPACITY, est.quota);
      }
    } catch (e) {}
    return CAPACITY;
  }
  function bytesText(s) {
    try { return new Blob([String(s)]).size; } catch (e) { return String(s).length; }
  }
  function formatBytes(n) {
    n = Math.max(0, Number(n) || 0);
    if (n < 1024) return n + ' B';
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + ' KB';
    return (n / (1024 * 1024)).toFixed(2) + ' MB';
  }
  function hashIndex(str, len) {
    var h = 0;
    for (var i = 0; i < str.length; i++) h = ((h << 5) - h + str.charCodeAt(i)) | 0;
    return Math.abs(h) % len;
  }
  function accentFor(id) { return PALETTE[hashIndex(String(id), PALETTE.length)]; }
  function letterFor(name) {
    var s = String(name || 'K').trim();
    return (s.charAt(0) || 'K').toUpperCase();
  }
  function iconMime(name) {
    var ext = String(name).split('.').pop().toLowerCase();
    if (ext === 'png') return 'image/png';
    if (ext === 'jpg' || ext === 'jpeg') return 'image/jpeg';
    if (ext === 'gif') return 'image/gif';
    if (ext === 'webp') return 'image/webp';
    if (ext === 'svg') return 'image/svg+xml';
    if (ext === 'bmp') return 'image/bmp';
    return 'application/octet-stream';
  }
  function mimeFor(name) {
    var ext = String(name).split('.').pop().toLowerCase();
    var map = {
      html: 'text/html', htm: 'text/html', ktml: 'text/html', css: 'text/css',
      js: 'text/javascript', mjs: 'text/javascript', json: 'application/json',
      txt: 'text/plain', md: 'text/markdown', xml: 'application/xml',
      svg: 'image/svg+xml', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
      gif: 'image/gif', webp: 'image/webp', mp3: 'audio/mpeg', m4a: 'audio/mp4',
      wav: 'audio/wav', mp4: 'video/mp4', webm: 'video/webm', mov: 'video/quicktime',
      woff: 'font/woff', woff2: 'font/woff2', ttf: 'font/ttf', otf: 'font/otf',
      ico: 'image/x-icon', pdf: 'application/pdf'
    };
    return map[ext] || 'application/octet-stream';
  }
  function isTextFile(name) {
    return /\.(html?|ktml|css|js|mjs|json|txt|md|xml|svg|webmanifest|plist|ktml)$/i.test(name);
  }
  function decodeText(u8) {
    try { return new TextDecoder('utf-8', { fatal: false }).decode(u8); }
    catch (e) { return String.fromCharCode.apply(null, u8); }
  }
  function bytesToBase64(u8) {
    var chunk = 0x8000, out = '';
    for (var i = 0; i < u8.length; i += chunk) {
      out += String.fromCharCode.apply(null, u8.subarray(i, Math.min(i + chunk, u8.length)));
    }
    return btoa(out);
  }
  function dataURLFor(u8, name) {
    return 'data:' + mimeFor(name) + ';base64,' + bytesToBase64(u8);
  }
  function blobToDataURL(blob) {
    return new Promise(function (resolve, reject) {
      var r = new FileReader();
      r.onload = function () { resolve(String(r.result)); };
      r.onerror = function () { reject(new Error('读取文件失败')); };
      r.readAsDataURL(blob);
    });
  }
  function downloadBlob(blob, filename) {
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    setTimeout(function () {
      URL.revokeObjectURL(a.href);
      a.remove();
    }, 800);
  }
  function normPath(path) {
    var parts = String(path || '').replace(/\\/g, '/').split('/');
    var out = [];
    parts.forEach(function (p) {
      if (!p || p === '.') return;
      if (p === '..') out.pop();
      else out.push(p);
    });
    return out.join('/');
  }
  function dirname(path) {
    var p = String(path || '');
    var i = p.lastIndexOf('/');
    return i >= 0 ? p.slice(0, i) : '';
  }
  function appRecord(id) {
    if (state.records[id]) return state.records[id];
    var rec = readJSON(LS.appPrefix + id, null);
    if (rec) state.records[id] = rec;
    return rec;
  }
  function iconFor(id, name) {
    var rec = appRecord(id);
    var icon = safeIcon(rec && rec.icon);
    if (icon) {
      return '<div class="app-icon" style="background-image:url(\'' + icon.replace(/'/g, '%27') + '\')"></div>';
    }
    return '<div class="app-icon" style="background:linear-gradient(145deg,' +
      accentFor(id) + ',' + shade(accentFor(id), -24) + ')">' + escapeHTML(letterFor(name)) + '</div>';
  }
  function shade(hex, percent) {
    var h = String(hex).replace('#', '');
    if (h.length !== 6) return hex;
    var n = parseInt(h, 16);
    var r = Math.max(0, Math.min(255, (n >> 16) + Math.round(255 * percent / 100)));
    var g = Math.max(0, Math.min(255, ((n >> 8) & 255) + Math.round(255 * percent / 100)));
    var b = Math.max(0, Math.min(255, (n & 255) + Math.round(255 * percent / 100)));
    return '#' + [r, g, b].map(function (v) { return ('0' + v.toString(16)).slice(-2); }).join('');
  }

  /* ---------------- 应用索引 ---------------- */

  function loadIndex() {
    var raw = lsGet(LS.index);
    var list;
    if (raw == null) {
      list = [];
    } else {
      try {
        list = JSON.parse(raw);
      } catch (e) {
        // 索引损坏：备份原始内容后按空索引处理，再由 reconcileIndex 从包记录恢复
        try { lsSet('kfw.index.corrupt.v1', raw); } catch (e2) {}
        list = [];
      }
    }
    if (!Array.isArray(list)) list = [];
    return list.filter(function (x) { return x && x.appId; });
  }

  function reconcileIndex() {
    var indexed = {};
    state.apps.forEach(function (a) { if (a && a.appId) indexed[a.appId] = true; });
    var orphanIds = [];
    lsKeys().forEach(function (k) {
      if (k.indexOf(LS.appPrefix) === 0) orphanIds.push(k.slice(LS.appPrefix.length));
    });
    var changed = false;
    orphanIds.forEach(function (id) {
      if (indexed[id]) return;
      var rec = readJSON(LS.appPrefix + id, null);
      if (rec && rec.appId) {
        state.apps.push({
          appId: rec.appId, name: rec.name || id, description: rec.description || '',
          version: rec.version || '1.0', caps: capsOf(rec.manifest), size: rec.size,
          fileCount: rec.fileCount, installedAt: rec.installedAt || Date.now(), entry: rec.entry
        });
        changed = true;
      } else {
        removeAppKeys(id); // 损坏的孤儿包：清理残留
        changed = true;
      }
    });
    if (changed) saveIndex();
  }

  function saveIndex() {
    writeJSON(LS.index, state.apps);
  }

  function capsOf(manifest) {
    var c = manifest && manifest.capabilities;
    if (Array.isArray(c)) return c.filter(function (x) { return typeof x === 'string'; });
    if (c && typeof c === 'object') {
      return Object.keys(c).filter(function (k) { return c[k]; });
    }
    return [];
  }

  function upsertIndex(meta) {
    var existing = state.apps.filter(function (a) { return a.appId !== meta.appId; });
    state.apps = existing.concat([meta]);
    saveIndex();
  }

  function removeAppKeys(id) {
    lsRemove(LS.appPrefix + id);
    lsRemove(LS.dataPrefix + id);
    lsRemove(LS.fsPrefix + id);
  }

  function storageUsed() {
    var total = 0;
    lsKeys().forEach(function (k) {
      if (!k || k.indexOf('kfw.') !== 0) return;
      var v = lsGet(k) || '';
      total += bytesText(k) + bytesText(v);
    });
    return total;
  }

  function renderStorage() {
    var used = storageUsed();
    var pct = Math.min(100, Math.round(used / CAPACITY * 1000) / 10);
    if (el.storageBar) el.storageBar.style.width = pct + '%';
    if (el.storageText) el.storageText.textContent = formatBytes(used);
    if (el.settingsStorage) el.settingsStorage.textContent = formatBytes(used);
    if (el.settingsStorageBar) el.settingsStorageBar.style.width = pct + '%';
    if (el.statSize) el.statSize.textContent = formatBytes(used);
    if (el.viewDisk && !el.viewDisk.hidden) renderDisk();
  }

  /* ---------------- 应用库 ---------------- */

  function filteredApps() {
    var q = state.query.trim().toLowerCase();
    var list = state.apps.slice();
    if (q) {
      list = list.filter(function (a) {
        return (String(a.name || '') + ' ' + String(a.appId || '') + ' ' + String(a.description || '')).toLowerCase().indexOf(q) >= 0;
      });
    }
    list.sort(function (a, b) {
      if (state.sort === 'name') return String(a.name || '').localeCompare(String(b.name || ''), 'zh-Hans');
      return Number(b.installedAt || 0) - Number(a.installedAt || 0);
    });
    return list;
  }

  function renderApps() {
    if (!el.appGrid) return;
    var list = filteredApps();
    el.appGrid.innerHTML = list.map(function (a) {
      var caps = (a.caps || []).slice(0, 4);
      var more = (a.caps || []).length - caps.length;
      var capHTML = caps.map(function (c) {
        return '<span class="cap">' + escapeHTML(CAP_NAMES[c] || c) + '</span>';
      }).join('');
      if (more > 0) capHTML += '<span class="cap more">+' + more + '</span>';
      return '<article class="app-card" data-id="' + escapeHTML(a.appId) + '" style="--card-accent:' + accentFor(a.appId) + '">' +
        '<div class="app-head">' + iconFor(a.appId, a.name) +
          '<div class="app-name"><b>' + escapeHTML(a.name || a.appId) + '</b><span>' + escapeHTML(a.appId) + '</span></div>' +
          '<button class="card-menu" data-menu="' + escapeHTML(a.appId) + '" title="管理应用">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></svg>' +
          '</button>' +
        '</div>' +
        '<p class="app-desc">' + escapeHTML(a.description || 'Kinter 小程序') + '</p>' +
        '<div class="app-caps">' + capHTML + '</div>' +
        '<div class="app-foot"><span class="app-size">' + formatBytes(a.size) + ' · ' + (a.fileCount || 0) + ' 个文件</span>' +
          '<button class="open-btn" data-open="' + escapeHTML(a.appId) + '">打开' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="m9 6 6 6-6 6"/></svg>' +
          '</button></div>' +
      '</article>';
    }).join('');
    el.appGrid.hidden = list.length === 0;
    if (el.emptyState) el.emptyState.hidden = list.length > 0;
    if (el.appCountText) {
      el.appCountText.textContent = state.apps.length ? ('共 ' + state.apps.length + ' 个，当前显示 ' + list.length + ' 个') : '还没有应用';
    }
    if (el.navCount) el.navCount.textContent = state.apps.length;
    if (el.statApps) el.statApps.textContent = state.apps.length;
    if (el.statCaps) el.statCaps.textContent = CAPABILITIES.length;
    renderStorage();
  }

  /* ---------------- 导入 ---------------- */

  function setImportLog(text) {
    if (!el.importLog) return;
    if (!text) {
      el.importLog.hidden = true;
      el.importLog.textContent = '';
      return;
    }
    el.importLog.hidden = false;
    el.importLog.textContent = text;
  }

  function pickZip() {
    showView('import');
    setTimeout(function () { if (el.zipInput) el.zipInput.click(); }, 30);
  }

  async function importZip(file) {
    if (!file) return;
    if (!/\.zip$/i.test(file.name) && file.type !== 'application/zip') {
      setImportLog('请选择 .zip 格式的小程序安装包。');
      return;
    }
    setImportLog('');
    if (el.importPreview) el.importPreview.hidden = true;
    state.preview = null;
    if (typeof DecompressionStream === 'undefined') {
      setImportLog('当前浏览器不支持解压 ZIP，请使用 Safari 16.4+ 或现代 Chrome / Edge。');
      toast('浏览器版本不支持解压', 2400);
      return;
    }
    if (file.size > 25 * 1024 * 1024) {
      setImportLog('安装包压缩后超过 25 MB，无法导入。');
      toast('安装包过大', 2000);
      return;
    }
    toast('正在解析安装包…', 1800);
    try {
      var buffer = await file.arrayBuffer();
      var zipFiles = await KinterZIP.unzip(buffer);
      var record = buildRecord(zipFiles, file.name);
      state.preview = record;
      renderPreview(record);
      toast('解析完成，可以安装', 1600);
    } catch (err) {
      console.error(err);
      setImportLog('导入失败：' + (err && err.message ? err.message : err));
      toast('导入失败', 2000);
    }
  }

  function buildRecord(zipFiles, fileName) {
    var names = Object.keys(zipFiles);
    if (!names.length) throw new Error('安装包是空的');
    var manifestPath = names.filter(function (n) { return /(^|\/)manifest\.json$/i.test(n); })
      .sort(function (a, b) { return a.length - b.length; })[0];
    if (!manifestPath) throw new Error('缺少 manifest.json');
    var root = manifestPath.indexOf('/') >= 0 ? manifestPath.slice(0, manifestPath.lastIndexOf('/') + 1) : '';

    var manifestText = decodeText(zipFiles[manifestPath]);
    var manifest;
    try { manifest = JSON.parse(manifestText); }
    catch (e) { throw new Error('manifest.json 不是合法 JSON'); }

    var appId = String(manifest.appId || manifest.id || '').trim();
    if (!/^[A-Za-z0-9._-]{2,80}$/.test(appId)) throw new Error('manifest.json 的 appId 非法');
    var name = String(manifest.name || manifest.title || appId).trim();

    var files = {};
    var totalSize = 0;
    names.forEach(function (full) {
      var short = full;
      if (root && short.indexOf(root) === 0) short = short.slice(root.length);
      short = normPath(short);
      if (!short || short === 'manifest.json') return;
      if (short.indexOf('__MACOSX/') === 0 || short.split('/').pop() === '.DS_Store') return;
      var bytes = zipFiles[full];
      if (!(bytes instanceof Uint8Array)) bytes = new Uint8Array(bytes);
      totalSize += bytes.length;
      if (isTextFile(short)) {
        files[short] = { kind: 'text', value: decodeText(bytes), size: bytes.length };
      } else {
        files[short] = { kind: 'b64', value: bytesToBase64(bytes), mime: mimeFor(short), size: bytes.length };
      }
    });

    var pages = [];
    if (Array.isArray(manifest.pages)) {
      manifest.pages.forEach(function (p) {
        if (typeof p === 'string') pages.push(p);
        else if (p && typeof p.path === 'string') pages.push(p.path);
        else if (p && p.path && p.path.src) pages.push(p.path.src);
      });
    }
    if (manifest.entry && typeof manifest.entry === 'string') pages.unshift(manifest.entry);
    if (!pages.length) pages.push('index');

    var entry = resolvePagePath({ files: files }, pages[0]);
    if (!entry) throw new Error('找不到入口页面（需要 index.html 或 index.ktml）');

    var iconName = String(manifest.icon || '').replace(/^\//, '');
    if (!iconName || !files[iconName]) {
      iconName = Object.keys(files).filter(function (n) {
        return /^(icon|logo|appicon)\.(png|jpe?g|webp|gif)$/i.test(n) || /(^|\/)(icon|logo)\.(png|jpe?g|webp)$/i.test(n);
      })[0];
    }
    var icon = '';
    if (iconName && files[iconName] && files[iconName].kind === 'b64') {
      var iconMime0 = files[iconName].mime || iconMime(iconName);
      if (/^image\//.test(iconMime0)) {
        icon = 'data:' + iconMime0 + ';base64,' + files[iconName].value;
      }
    }

    var total = bytesText(JSON.stringify({ files: files, manifest: manifest, icon: icon }));
    if (total > MAX_APP_BYTES) {
      throw new Error('应用解压后约 ' + formatBytes(total) + '，超过浏览器 LocalStorage 可用的 ' + formatBytes(MAX_APP_BYTES) + '，请精简资源');
    }

    return {
      appId: appId,
      name: name,
      description: String(manifest.description || manifest.desc || ''),
      version: String(manifest.version || '1.0'),
      manifest: manifest,
      pages: pages,
      entry: entry,
      files: files,
      icon: icon,
      size: totalSize,
      fileCount: Object.keys(files).length,
      installedAt: Date.now(),
      zipName: fileName
    };
  }

  function renderPreview(record) {
    if (!el.importPreview) return;
    var caps = (record.manifest.capabilities && Array.isArray(record.manifest.capabilities))
      ? record.manifest.capabilities : capsOf(record.manifest);
    el.importPreview.hidden = false;
    el.importPreview.innerHTML =
      '<div class="preview-head">' +
        iconForPreview(record) +
        '<div><b>' + escapeHTML(record.name) + '</b><span>' + escapeHTML(record.appId) + ' · v' + escapeHTML(record.version) + '</span></div>' +
      '</div>' +
      '<div class="preview-meta">' +
        '<div><strong>' + formatBytes(record.size) + '</strong><span>解压后大小</span></div>' +
        '<div><strong>' + record.fileCount + '</strong><span>文件</span></div>' +
        '<div><strong>' + escapeHTML(record.entry) + '</strong><span>入口页面</span></div>' +
      '</div>' +
      (caps.length ? '<div class="preview-caps">' + caps.map(function (c) {
        return '<span class="cap">' + escapeHTML(CAP_NAMES[c] || c) + '</span>';
      }).join('') + '</div>' : '') +
      '<div class="preview-actions">' +
        '<button class="btn" id="cancelPreview">取消</button>' +
        '<button class="btn primary" id="installPreview">安装到应用库</button>' +
      '</div>';
    var cancel = $('cancelPreview');
    var install = $('installPreview');
    if (cancel) cancel.onclick = function () {
      state.preview = null;
      el.importPreview.hidden = true;
    };
    if (install) install.onclick = function () { installPreview(); };
  }

  function iconForPreview(record) {
    var icon = safeIcon(record && record.icon);
    if (icon) {
      return '<div class="app-icon" style="background-image:url(\'' + icon.replace(/'/g, '%27') + '\')"></div>';
    }
    return '<div class="app-icon" style="background:linear-gradient(145deg,' + accentFor(record.appId) + ',' +
      shade(accentFor(record.appId), -24) + ')">' + escapeHTML(letterFor(record.name)) + '</div>';
  }

  async function installPreview() {
    var record = state.preview;
    if (!record) return;
    var appKey = LS.appPrefix + record.appId;
    var old = lsGet(appKey);
    var text = JSON.stringify(record);
    var prevApps = state.apps.slice();
    try {
      if (text.length > MAX_APP_BYTES) throw new Error('应用过大，无法写入 LocalStorage');
      var capacity = await probeCapacity();
      var projected = storageUsed() - (old ? bytesText(old) : 0) + bytesText(text);
      if (projected > capacity * 0.92) throw new Error('LocalStorage 空间不足，请先删除不用的应用或清理数据');

      // 事务第一步：写应用包，写后回读校验
      lsSet(appKey, text);
      if (lsGet(appKey) !== text) throw new Error('应用包写入校验失败，未完成安装');

      // 事务第二步：写索引；失败则回滚应用包与内存状态
      var meta = {
        appId: record.appId,
        name: record.name,
        description: record.description,
        version: record.version,
        caps: capsOf(record.manifest),
        size: record.size,
        fileCount: record.fileCount,
        installedAt: record.installedAt,
        entry: record.entry
      };
      try {
        state.records[record.appId] = record;
        upsertIndex(meta);
      } catch (idxErr) {
        state.apps = prevApps;
        delete state.records[record.appId];
        if (old != null) lsSet(appKey, old); else lsRemove(appKey);
        throw idxErr;
      }
      state.preview = null;
      if (el.importPreview) el.importPreview.hidden = true;
      setImportLog('');
      renderApps();
      renderSettings();
      showView('apps');
      toast('已安装「' + record.name + '」', 2200);
    } catch (err) {
      console.error(err);
      setImportLog('安装失败：' + (err && err.message ? err.message : err));
    }
  }

  /* ---------------- 设置与数据 ---------------- */

  function renderSettings() {
    if (!el.dataList) return;
    if (!state.apps.length) {
      el.dataList.innerHTML = '<div class="empty-line">还没有安装任何小程序。</div>';
    } else {
      el.dataList.innerHTML = state.apps.slice().sort(function (a, b) {
        return String(a.name).localeCompare(String(b.name), 'zh-Hans');
      }).map(function (a) {
        var rec = appRecord(a.appId);
        var appBytes = rec ? bytesText(JSON.stringify(rec)) : 0;
        var dataBytes = bytesText(lsGet(LS.dataPrefix + a.appId) || '') +
          bytesText(lsGet(LS.fsPrefix + a.appId) || '');
        return '<div class="data-row">' +
          '<div class="data-dot" style="background:' + accentFor(a.appId) + '">' + escapeHTML(letterFor(a.name)) + '</div>' +
          '<div class="data-name"><b>' + escapeHTML(a.name) + '</b><span>' + escapeHTML(a.appId) + '</span></div>' +
          '<span class="data-size">' + formatBytes(appBytes + dataBytes) + '</span>' +
          '<button class="data-manage" data-manage="' + escapeHTML(a.appId) + '" title="查看与管理应用数据">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 12 18.5 2.5 12Z"/><circle cx="12" cy="12" r="3"/></svg>' +
          '</button>' +
          '<button class="data-del" data-delete="' + escapeHTML(a.appId) + '" title="删除应用与数据">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/></svg>' +
          '</button>' +
        '</div>';
      }).join('');
    }
    renderStorage();
    refreshPermissions();
  }

  function appDataStats(id) {
    var rec = appRecord(id);
    return {
      packageBytes: rec ? bytesText(JSON.stringify(rec)) : 0,
      storageBytes: bytesText(lsGet(LS.dataPrefix + id) || ''),
      fsBytes: bytesText(lsGet(LS.fsPrefix + id) || ''),
      packageFiles: rec ? Object.keys(rec.files || {}).length : 0
    };
  }

  function valuePreview(value) {
    var text;
    try { text = typeof value === 'string' ? value : JSON.stringify(value); }
    catch (e) { text = String(value); }
    if (text == null) text = String(value);
    return text.length > 180 ? text.slice(0, 180) + '…' : text;
  }

  function openDataManager(id) {
    var meta = state.apps.filter(function (a) { return a.appId === id; })[0];
    var rec = appRecord(id);
    if (!meta && !rec) { toast('应用不存在', 1600); return; }
    var mask = document.createElement('div');
    mask.className = 'modal-mask dm-mask';
    mask.innerHTML =
      '<div class="modal-card dm-card">' +
        '<div class="dm-head">' +
          '<div class="dm-title">' + iconForPreview(rec || { appId: id, name: meta ? meta.name : id }) +
            '<div><h2>' + escapeHTML(meta ? meta.name : id) + '</h2><span>' + escapeHTML(id) + '</span></div>' +
          '</div>' +
          '<button class="dm-close" data-act="close" title="关闭">×</button>' +
        '</div>' +
        '<div class="dm-body"></div>' +
      '</div>';
    el.modalRoot.appendChild(mask);
    var entry = { close: close };
    state.modals.push(entry);

    function close() {
      state.modals = state.modals.filter(function (m) { return m !== entry; });
      mask.remove();
    }

    function refresh() {
      var current = appRecord(id);
      var storage = dataScope(id);
      var fs = fsScope(id);
      var stats = appDataStats(id);
      var storageKeys = Object.keys(storage);
      var fileKeys = Object.keys(fs).filter(function (k) { return k.indexOf('file:') === 0; }).map(function (k) { return k.slice(5); });
      var dirKeys = Object.keys(fs).filter(function (k) { return k.indexOf('dir:') === 0; }).map(function (k) { return k.slice(4); });
      var body = mask.querySelector('.dm-body');
      var oldScroll = body.scrollTop;

      var storageRows = storageKeys.map(function (key) {
        return '<div class="dm-row">' +
          '<div class="dm-main"><b>' + escapeHTML(key) + '</b><span class="dm-val">' + escapeHTML(valuePreview(storage[key])) + '</span></div>' +
          '<div class="dm-row-tools">' +
            '<button class="dm-mini" data-act="edit-storage" data-key="' + escapeHTML(key) + '">编辑</button>' +
            '<button class="dm-mini danger" data-act="del-storage" data-key="' + escapeHTML(key) + '">删除</button>' +
          '</div>' +
        '</div>';
      }).join('');

      var fileRows = fileKeys.map(function (path) {
        var file = fs['file:' + path];
        var isText = file && typeof file.text === 'string';
        var size = isText ? bytesText(file.text) : bytesText(file && file.b64 || '');
        return '<div class="dm-row">' +
          '<div class="dm-main"><b>' + escapeHTML(path) + '</b><span class="dm-val">' +
            (isText ? escapeHTML(valuePreview(file.text)) : '二进制 / Base64') + ' · ' + formatBytes(size) +
          '</span></div>' +
          '<div class="dm-row-tools">' +
            (isText ? '<button class="dm-mini" data-act="edit-file" data-file="' + escapeHTML(path) + '">编辑</button>' : '') +
            '<button class="dm-mini danger" data-act="del-file" data-file="' + escapeHTML(path) + '">删除</button>' +
          '</div>' +
        '</div>';
      }).join('');

      var pkgFiles = current ? Object.keys(current.files || {}) : [];
      var pkgRows = pkgFiles.slice(0, 40).map(function (name) {
        var f = current.files[name];
        return '<div class="dm-pkg-row"><span>' + escapeHTML(name) + '</span><b>' +
          (f.kind === 'text' ? 'text' : 'binary') + ' · ' + formatBytes(f.size || 0) + '</b></div>';
      }).join('');

      body.innerHTML =
        '<div class="dm-stat-grid">' +
          '<div><strong>' + formatBytes(stats.packageBytes) + '</strong><span>应用包</span></div>' +
          '<div><strong>' + formatBytes(stats.storageBytes) + '</strong><span>Storage</span></div>' +
          '<div><strong>' + formatBytes(stats.fsBytes) + '</strong><span>虚拟文件</span></div>' +
        '</div>' +
        '<div class="dm-section">' +
          '<div class="dm-section-head">' +
            '<div><h3>Storage</h3><p>wx.setStorage 写入的键值数据 · ' + storageKeys.length + ' 个键</p></div>' +
            '<div class="dm-tools"><button class="dm-mini" data-act="add-storage">新增键</button>' +
            (storageKeys.length ? '<button class="dm-mini danger" data-act="clear-storage">清空</button>' : '') + '</div>' +
          '</div>' +
          (storageRows || '<div class="dm-empty">暂无 Storage 数据。运行小程序后，写入的数据会出现在这里。</div>') +
        '</div>' +
        '<div class="dm-section">' +
          '<div class="dm-section-head">' +
            '<div><h3>虚拟文件</h3><p>kinter://' + escapeHTML(id) + '/data · ' + fileKeys.length + ' 个文件' +
              (dirKeys.length ? '，' + dirKeys.length + ' 个目录' : '') + '</p></div>' +
            (fileKeys.length ? '<div class="dm-tools"><button class="dm-mini danger" data-act="clear-files">清空</button></div>' : '') +
          '</div>' +
          (fileRows || '<div class="dm-empty">暂无虚拟文件。' +
            (dirKeys.length ? '目录：' + dirKeys.map(escapeHTML).join('、') : '') + '</div>') +
        '</div>' +
        '<details class="dm-details">' +
          '<summary>应用包内容 · ' + pkgFiles.length + ' 个文件</summary>' +
          '<div class="dm-pkg-list">' + (pkgRows || '<div class="dm-empty">应用包为空</div>') +
          (pkgFiles.length > 40 ? '<div class="dm-empty">还有 ' + (pkgFiles.length - 40) + ' 个文件未显示</div>' : '') +
          '</div>' +
        '</details>' +
        '<div class="dm-footer">' +
          '<button class="dm-btn" data-act="export">导出应用数据</button>' +
          '<button class="dm-btn danger" data-act="delete-app">删除应用</button>' +
          '<button class="dm-btn primary" data-act="close">完成</button>' +
        '</div>';
      body.scrollTop = oldScroll;
    }

    mask.addEventListener('click', async function (e) {
      if (e.target === mask) { close(); return; }
      var button = e.target.closest ? e.target.closest('[data-act]') : null;
      if (!button) return;
      var act = button.getAttribute('data-act');
      if (act === 'close') { close(); return; }
      if (act === 'add-storage') {
        openStorageEditor(id, '', '', true, refresh);
        return;
      }
      if (act === 'edit-storage') {
        var key = button.getAttribute('data-key');
        var storage = dataScope(id);
        openStorageEditor(id, key, JSON.stringify(storage[key], null, 2), false, refresh);
        return;
      }
      if (act === 'del-storage') {
        var delKey = button.getAttribute('data-key');
        var ok1 = await uiModal({
          title: '删除键「' + delKey + '」？',
          content: '只会删除这个小程序的这一条 Storage 数据。',
          confirmText: '删除',
          danger: true
        });
        if (!ok1) return;
        var ds = dataScope(id);
        delete ds[delKey];
        saveDataScope(id, ds);
        refresh(); renderSettings(); renderStorage();
        toast('已删除键', 1300);
        return;
      }
      if (act === 'clear-storage') {
        var ok2 = await uiModal({
          title: '清空 Storage？',
          content: '这个小程序的所有 wx.setStorage 键值都会删除，应用本身保留。',
          confirmText: '清空 Storage',
          danger: true
        });
        if (!ok2) return;
        lsRemove(LS.dataPrefix + id);
        refresh(); renderSettings(); renderStorage();
        toast('Storage 已清空', 1400);
        return;
      }
      if (act === 'edit-file') {
        var editPath = button.getAttribute('data-file');
        var fsEdit = fsScope(id);
        var file = fsEdit['file:' + editPath];
        if (!file || typeof file.text !== 'string') return;
        openFileEditor(id, editPath, file.text, refresh);
        return;
      }
      if (act === 'del-file') {
        var delPath = button.getAttribute('data-file');
        var ok3 = await uiModal({
          title: '删除文件？',
          content: 'kinter://' + id + '/data/' + delPath,
          confirmText: '删除',
          danger: true
        });
        if (!ok3) return;
        var fsDel = fsScope(id);
        delete fsDel['file:' + delPath];
        saveFs(id, fsDel);
        refresh(); renderSettings(); renderStorage();
        toast('文件已删除', 1300);
        return;
      }
      if (act === 'clear-files') {
        var ok4 = await uiModal({
          title: '清空虚拟文件？',
          content: '这个小程序通过 wx.writeFile 写入的文件都会删除。',
          confirmText: '清空文件',
          danger: true
        });
        if (!ok4) return;
        lsRemove(LS.fsPrefix + id);
        refresh(); renderSettings(); renderStorage();
        toast('虚拟文件已清空', 1400);
        return;
      }
      if (act === 'export') {
        exportAppData(id);
        return;
      }
      if (act === 'delete-app') {
        close();
        await deleteApp(id);
        return;
      }
    });

    refresh();
  }

  function openStorageEditor(id, key, initialText, isNew, onSaved) {
    var mask = document.createElement('div');
    mask.className = 'modal-mask dm-editor-mask';
    mask.innerHTML =
      '<div class="modal-card dm-editor">' +
        '<h2>' + (isNew ? '新增 Storage 键' : '编辑 Storage') + '</h2>' +
        '<label class="dm-label">键名' +
          '<input class="dm-input" id="dmKeyInput" value="' + escapeHTML(key) + '" ' + (isNew ? '' : 'readonly') + ' placeholder="例如 user.profile">' +
        '</label>' +
        '<label class="dm-label">值 <small>支持 JSON，也可以直接输入纯文本</small>' +
          '<textarea class="dm-textarea" id="dmValueInput" spellcheck="false">' + escapeHTML(initialText) + '</textarea>' +
        '</label>' +
        '<div class="dm-editor-actions">' +
          '<button class="dm-btn" data-act="cancel">取消</button>' +
          '<button class="dm-btn primary" data-act="save">保存</button>' +
        '</div>' +
      '</div>';
    el.modalRoot.appendChild(mask);
    var entry = { close: close };
    state.modals.push(entry);
    var keyInput = mask.querySelector('#dmKeyInput');
    var valueInput = mask.querySelector('#dmValueInput');
    function close() {
      state.modals = state.modals.filter(function (m) { return m !== entry; });
      mask.remove();
    }
    mask.addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('[data-act]') : null;
      if (!b) {
        if (e.target === mask) close();
        return;
      }
      if (b.getAttribute('data-act') === 'cancel') { close(); return; }
      if (b.getAttribute('data-act') === 'save') {
        var newKey = String(keyInput.value || '').trim();
        if (!newKey) { toast('键名不能为空', 1400); keyInput.focus(); return; }
        var raw = valueInput.value;
        var value;
        try { value = JSON.parse(raw); }
        catch (e) { value = raw; }
        var storage = dataScope(id);
        storage[newKey] = value;
        saveDataScope(id, storage);
        close();
        if (onSaved) onSaved();
        renderSettings(); renderStorage();
        toast(isNew ? '已新增键' : '已保存', 1400);
      }
    });
    setTimeout(function () { if (isNew) keyInput.focus(); else valueInput.focus(); }, 30);
  }

  function openFileEditor(id, path, initialText, onSaved) {
    var mask = document.createElement('div');
    mask.className = 'modal-mask dm-editor-mask';
    mask.innerHTML =
      '<div class="modal-card dm-editor">' +
        '<h2>编辑虚拟文件</h2>' +
        '<div class="dm-file-path">kinter://' + escapeHTML(id) + '/data/' + escapeHTML(path) + '</div>' +
        '<textarea class="dm-textarea tall" id="dmFileInput" spellcheck="false">' + escapeHTML(initialText) + '</textarea>' +
        '<div class="dm-editor-actions">' +
          '<button class="dm-btn" data-act="cancel">取消</button>' +
          '<button class="dm-btn primary" data-act="save">保存</button>' +
        '</div>' +
      '</div>';
    el.modalRoot.appendChild(mask);
    var entry = { close: close };
    state.modals.push(entry);
    var input = mask.querySelector('#dmFileInput');
    function close() {
      state.modals = state.modals.filter(function (m) { return m !== entry; });
      mask.remove();
    }
    mask.addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('[data-act]') : null;
      if (!b) {
        if (e.target === mask) close();
        return;
      }
      if (b.getAttribute('data-act') === 'save') {
        var fs = fsScope(id);
        fs['file:' + path] = { text: input.value };
        saveFs(id, fs);
        close();
        if (onSaved) onSaved();
        renderSettings(); renderStorage();
        toast('文件已保存', 1400);
      } else {
        close();
      }
    });
    setTimeout(function () { input.focus(); }, 30);
  }

  function exportAppData(id) {
    var meta = state.apps.filter(function (a) { return a.appId === id; })[0];
    var rec = appRecord(id);
    var payload = {
      format: 'kinter-for-web-appdata',
      version: 1,
      appId: id,
      name: meta ? meta.name : (rec ? rec.name : id),
      exportedAt: new Date().toISOString(),
      storage: dataScope(id),
      files: fsScope(id),
      manifest: rec ? rec.manifest : null
    };
    downloadBlob(new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' }),
      'KinterData-' + id + '-' + new Date().toISOString().slice(0, 10) + '.json');
    toast('应用数据已导出', 1400);
  }

  async function deleteApp(id) {
    var meta = state.apps.filter(function (a) { return a.appId === id; })[0];
    var ok = await uiModal({
      title: '删除「' + (meta ? meta.name : id) + '」？',
      content: '应用包、应用数据与虚拟文件都会从 LocalStorage 删除，此操作不可恢复。',
      confirmText: '删除',
      danger: true
    });
    if (!ok) return;
    removeAppKeys(id);
    delete state.records[id];
    state.apps = state.apps.filter(function (a) { return a.appId !== id; });
    saveIndex();
    renderApps();
    renderSettings();
    toast('已删除', 1500);
  }

  function clearAll() {
    uiModal({
      title: '清空全部数据？',
      content: '所有小程序、应用数据、虚拟文件与设置都会删除。',
      confirmText: '全部清空',
      danger: true
    }).then(function (ok) {
      if (!ok) return;
      // 只枚举并删除 kfw.* 前缀键；lsRemove 内部已吞掉删除异常，单键失败不中断循环
      var keys = lsKeys().filter(function (k) { return k && k.indexOf('kfw.') === 0; });
      keys.forEach(function (k) { lsRemove(k); });
      state.apps = [];
      state.records = {};
      state.settings = {};
      renderApps();
      renderSettings();
      applyTheme();
      toast('已清空', 1600);
    });
  }

  function exportLibrary() {
    var keys = {};
    lsKeys().forEach(function (k) {
      if (k && k.indexOf('kfw.') === 0) keys[k] = lsGet(k);
    });
    var payload = { format: 'kinter-for-web-backup', version: 1, exportedAt: new Date().toISOString(), keys: keys };
    downloadBlob(new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' }),
      'KinterForWeb-backup-' + new Date().toISOString().slice(0, 10) + '.json');
    toast('备份已导出', 1500);
  }

  function validateBackupKeys(keys, map) {
    keys.forEach(function (k) {
      var parsed;
      try { parsed = JSON.parse(map[k]); }
      catch (e) { throw new Error('备份键不是合法 JSON：' + k); }
      if (k === LS.index) {
        if (!Array.isArray(parsed)) throw new Error('备份索引格式非法（应为数组）');
        parsed.forEach(function (a) {
          if (!a || typeof a.appId !== 'string') throw new Error('备份索引条目缺少 appId');
        });
      } else if (k === LS.settings) {
        if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) throw new Error('备份设置格式非法');
      } else if (k.indexOf(LS.appPrefix) === 0) {
        if (typeof parsed !== 'object' || parsed === null || typeof parsed.appId !== 'string' || typeof parsed.files !== 'object') {
          throw new Error('备份应用包记录非法：' + k);
        }
      } else if (k.indexOf(LS.dataPrefix) === 0 || k.indexOf(LS.fsPrefix) === 0) {
        if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) throw new Error('备份数据格式非法：' + k);
      }
    });
  }

  async function importBackup(file) {
    if (!file) return;
    try {
      var payload = JSON.parse(await file.text());
      if (!payload || payload.format !== 'kinter-for-web-backup' || !payload.keys) throw new Error('不是 Kinter for Web 备份');
      var ok = await uiModal({
        title: '导入备份？',
        content: '会用备份中的小程序与数据覆盖同 appId 的现有内容。',
        confirmText: '导入'
      });
      if (!ok) return;
      var keys = Object.keys(payload.keys).filter(function (k) {
        return k.indexOf('kfw.') === 0 && typeof payload.keys[k] === 'string';
      });
      validateBackupKeys(keys, payload.keys);
      var total = 0;
      keys.forEach(function (k) { total += bytesText(payload.keys[k]); });
      var capacity = await probeCapacity();
      if (total > capacity * 0.92) throw new Error('备份超过浏览器 LocalStorage 容量');
      var snapshot = {};
      keys.forEach(function (k) { snapshot[k] = lsGet(k); });
      var failed = [];
      keys.forEach(function (k) {
        try { lsSet(k, payload.keys[k]); } catch (e) { failed.push(k); }
      });
      if (failed.length) {
        // 回滚已覆盖的键，避免半写状态
        keys.forEach(function (k) {
          var old = snapshot[k];
          if (old == null) lsRemove(k); else lsSet(k, old);
        });
        throw new Error('部分键写入失败（' + failed.length + ' 条），已恢复原数据，请清理空间后重试');
      }
      state.records = {};
      state.apps = loadIndex();
      reconcileIndex();
      state.settings = readJSON(LS.settings, {});
      renderApps();
      renderSettings();
      applyTheme();
      toast('备份已导入', 1800);
    } catch (err) {
      uiModal({ title: '导入失败', content: String(err && err.message || err), confirmText: '知道了' });
    }
  }

  /* ---------------- 主题 ---------------- */

  function loadSettings() {
    state.settings = readJSON(LS.settings, {});
    if (!state.settings.theme) state.settings.theme = 'system';
  }

  function saveSettings() {
    writeJSON(LS.settings, state.settings);
  }

  function applyTheme() {
    var dark;
    if (state.settings.theme === 'dark') dark = true;
    else if (state.settings.theme === 'light') dark = false;
    else dark = !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.body.classList.toggle('dark', dark);
    if (el.themeToggle) el.themeToggle.title = dark ? '当前：深色，点击切换' : '当前：浅色，点击切换';
  }

  function toggleTheme() {
    state.settings.theme = document.body.classList.contains('dark') ? 'light' : 'dark';
    saveSettings();
    applyTheme();
  }

  /* ---------------- 权限状态 ---------------- */

  var PERM_ICONS = {
    camera: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 8h3l1.5-2h7L17 8h3v11H4z"/><circle cx="12" cy="13" r="3.2"/></svg>',
    mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>',
    pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 21s7-6.2 7-12a7 7 0 1 0-14 0c0 5.8 7 12 7 12Z"/><circle cx="12" cy="9" r="2.4"/></svg>',
    bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 20a2 2 0 0 0 4 0"/></svg>',
    clip: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="6" y="4" width="12" height="16" rx="2"/><path d="M9 8h6M9 12h6"/></svg>',
    drive: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/><path d="M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6"/></svg>'
  };

  function statusLabel(s) {
    if (s === 'granted') return { text: '已允许', cls: 'ok' };
    if (s === 'denied') return { text: '已拒绝', cls: 'off' };
    if (s === 'prompt') return { text: '使用时询问', cls: 'warn' };
    return { text: '按需申请', cls: 'warn' };
  }

  async function queryPerm(p) {
    if (p.query === 'notifications') {
      if (!('Notification' in window)) return 'unsupported';
      return Notification.permission;
    }
    if (navigator.permissions && navigator.permissions.query) {
      try {
        var s = await navigator.permissions.query({ name: p.query });
        return s.state;
      } catch (e) { return 'prompt'; }
    }
    return 'prompt';
  }

  async function refreshPermissions() {
    if (!el.permList) return;
    var rows = [];
    for (var i = 0; i < PERMISSIONS.length; i++) {
      var p = PERMISSIONS[i];
      var st = await queryPerm(p);
      var lab = statusLabel(st);
      rows.push('<div class="perm-row" data-perm="' + p.id + '">' +
        '<div class="perm-icon">' + (PERM_ICONS[p.icon] || '') + '</div>' +
        '<div class="perm-name"><b>' + p.name + '</b><span>' + p.desc + '</span></div>' +
        '<span class="perm-state ' + lab.cls + '">' + lab.text + '</span>' +
      '</div>');
    }
    el.permList.innerHTML = rows.join('');
  }

  async function requestPermission(id) {
    try {
      if (id === 'camera' || id === 'microphone') {
        var stream = await navigator.mediaDevices.getUserMedia(id === 'camera' ? { video: true } : { audio: true });
        stream.getTracks().forEach(function (t) { t.stop(); });
      } else if (id === 'geolocation') {
        await new Promise(function (resolve, reject) {
          navigator.geolocation.getCurrentPosition(resolve, reject, { timeout: 8000 });
        });
      } else if (id === 'notifications') {
        if ('Notification' in window) await Notification.requestPermission();
      } else {
        toast('该权限由浏览器在首次使用对应能力时询问', 2200);
        return;
      }
      toast('权限已更新', 1400);
    } catch (err) {
      toast('未获得授权', 1800);
    }
    refreshPermissions();
  }

  /* ---------------- 文件浏览器 / LocalStorage 磁盘 ---------------- */

  function diskNorm(path) {
    return '/' + String(path || '').split('/').filter(Boolean).join('/');
  }

  function diskUsedBytes() {
    var total = 0;
    lsKeys().forEach(function (k) {
      if (!k) return;
      total += bytesText(k) + bytesText(lsGet(k) || '');
    });
    return total;
  }

  function diskAppIds() {
    var ids = {};
    state.apps.forEach(function (a) { if (a && a.appId) ids[a.appId] = true; });
    lsKeys().forEach(function (k) {
      [LS.appPrefix, LS.dataPrefix, LS.fsPrefix].forEach(function (prefix) {
        if (k.indexOf(prefix) === 0) ids[k.slice(prefix.length)] = true;
      });
    });
    return Object.keys(ids).sort(function (a, b) {
      return String(diskMetaFor(a).name).localeCompare(String(diskMetaFor(b).name), 'zh-Hans');
    });
  }

  function diskMetaFor(id) {
    var meta = state.apps.filter(function (a) { return a.appId === id; })[0];
    var rec = appRecord(id);
    return {
      appId: id,
      name: (meta && meta.name) || (rec && rec.name) || id,
      meta: meta || null,
      rec: rec || null
    };
  }

  function diskBadge(name) {
    var ext = String(name || '').split('.').pop().toUpperCase();
    if (ext === 'KTML') return 'KTM';
    if (ext === 'JSON') return 'JSON';
    if (ext === 'HTML' || ext === 'HTM') return 'HTML';
    if (ext === 'PNG' || ext === 'JPG' || ext === 'JPEG' || ext === 'GIF' || ext === 'WEBP') return 'IMG';
    return ext.length <= 4 ? ext : 'FILE';
  }

  function diskTypeFor(name, kind) {
    var ext = String(name || '').split('.').pop().toLowerCase();
    if (ext === 'json') return 'JSON 文件';
    if (ext === 'html' || ext === 'htm' || ext === 'ktml') return '页面文件';
    if (ext === 'css') return '样式表';
    if (ext === 'js' || ext === 'mjs') return '脚本';
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'].indexOf(ext) >= 0) return '图片';
    if (['mp3', 'm4a', 'wav', 'aac'].indexOf(ext) >= 0) return '音频';
    if (['mp4', 'webm', 'mov'].indexOf(ext) >= 0) return '视频';
    if (ext === 'txt' || ext === 'md') return '文本';
    if (kind === 'text') return '文本';
    return '文件';
  }

  function diskFolderEntry(name, path, size, type) {
    return {
      name: name, path: path, type: type || '文件夹', size: size || 0,
      isFolder: true, badge: 'folder', scope: 'folder'
    };
  }

  function diskSystemEntries() {
    return [LS.index, LS.settings].filter(function (k) {
      return lsGet(k) !== null;
    }).map(function (key) {
      var raw = lsGet(key) || '';
      return {
        name: key,
        path: '/系统/' + key,
        type: key === LS.index ? '应用索引' : '偏好设置',
        size: bytesText(raw),
        badge: 'SYS', scope: 'system', key: key, isFolder: false
      };
    });
  }

  function diskRawEntries() {
    var out = [];
    lsKeys().forEach(function (key) {
      if (!key) return;
      var raw = lsGet(key) || '';
      out.push({
        name: key,
        path: '/原始存储/' + key,
        type: 'LocalStorage 记录',
        size: bytesText(key) + bytesText(raw),
        badge: 'LS', scope: 'raw', key: key, isFolder: false
      });
    });
    return out.sort(function (a, b) { return a.name.localeCompare(b.name); });
  }

  function diskRootEntries() {
    var systemSize = diskSystemEntries().reduce(function (n, x) { return n + x.size; }, 0);
    var appSize = diskAppIds().reduce(function (n, id) {
      var rec = appRecord(id);
      return n + (rec ? bytesText(JSON.stringify(rec)) : 0) +
        bytesText(lsGet(LS.dataPrefix + id) || '') +
        bytesText(lsGet(LS.fsPrefix + id) || '');
    }, 0);
    return [
      diskFolderEntry('系统', '/系统', systemSize, '文件夹'),
      diskFolderEntry('应用', '/应用', appSize, '文件夹 · ' + diskAppIds().length + ' 个应用'),
      diskFolderEntry('原始存储', '/原始存储', diskUsedBytes(), '文件夹 · ' + lsCount() + ' 条记录')
    ];
  }

  function diskAppEntries(id) {
    var rec = appRecord(id);
    var storage = dataScope(id);
    var fs = fsScope(id);
    var pkgSize = rec ? bytesText(JSON.stringify(rec)) : 0;
    var dataSize = bytesText(lsGet(LS.dataPrefix + id) || '');
    var fsSize = bytesText(lsGet(LS.fsPrefix + id) || '');
    var pkgCount = rec ? Object.keys(rec.files || {}).filter(function (n) { return n !== 'manifest.json'; }).length + 1 : 0;
    var dataCount = Object.keys(storage).length;
    var fsCount = Object.keys(fs).filter(function (k) { return k.indexOf('file:') === 0; }).length;
    return [
      diskFolderEntry('应用包', '/应用/' + id + '/应用包', pkgSize, '文件夹 · ' + pkgCount + ' 个文件'),
      diskFolderEntry('Storage', '/应用/' + id + '/Storage', dataSize, '文件夹 · ' + dataCount + ' 个键'),
      diskFolderEntry('虚拟文件', '/应用/' + id + '/虚拟文件', fsSize, '文件夹 · ' + fsCount + ' 个文件')
    ];
  }

  function diskPackageEntries(id, rel) {
    var rec = appRecord(id);
    if (!rec) return [];
    rel = String(rel || '').replace(/^\/|\/$/g, '');
    var base = '/应用/' + id + '/应用包';
    var prefix = rel ? rel + '/' : '';
    var groups = {};
    var files = [];
    Object.keys(rec.files || {}).forEach(function (fileName) {
      if (!rel && fileName === 'manifest.json') return;
      if (fileName.indexOf(prefix) !== 0) return;
      var rest = fileName.slice(prefix.length);
      if (!rest) return;
      var slash = rest.indexOf('/');
      if (slash >= 0) {
        var seg = rest.slice(0, slash);
        if (!groups[seg]) groups[seg] = { size: 0, count: 0 };
        groups[seg].size += rec.files[fileName].size || 0;
        groups[seg].count++;
      } else {
        var f = rec.files[fileName];
        files.push({
          name: rest,
          path: base + '/' + fileName,
          type: diskTypeFor(rest, f.kind),
          size: f.size || bytesText(f.value || ''),
          badge: diskBadge(rest),
          scope: 'package', appId: id, fileName: fileName, file: f,
          isFolder: false, mime: f.mime || mimeFor(rest)
        });
      }
    });
    var entries = Object.keys(groups).map(function (seg) {
      var fullRel = rel ? rel + '/' + seg : seg;
      return diskFolderEntry(seg, base + '/' + fullRel, groups[seg].size, '文件夹 · ' + groups[seg].count + ' 项');
    });
    if (!rel) {
      var manifestSize = bytesText(JSON.stringify(rec.manifest || {}));
      entries.unshift({
        name: 'manifest.json',
        path: base + '/manifest.json',
        type: '应用清单',
        size: manifestSize,
        badge: 'JSON',
        scope: 'manifest', appId: id, isFolder: false, mime: 'application/json'
      });
    }
    return entries.concat(files);
  }

  function diskFsEntries(id, rel) {
    var fs = fsScope(id);
    rel = String(rel || '').replace(/^\/|\/$/g, '');
    var base = '/应用/' + id + '/虚拟文件';
    var prefix = rel ? rel + '/' : '';
    var groups = {};
    var files = [];
    function addFolder(seg) {
      if (!groups[seg]) groups[seg] = { size: 0, count: 0 };
    }
    Object.keys(fs).filter(function (k) { return k.indexOf('file:') === 0; }).forEach(function (key) {
      var fileName = key.slice(5);
      if (fileName.indexOf(prefix) !== 0) return;
      var rest = fileName.slice(prefix.length);
      if (!rest) return;
      var slash = rest.indexOf('/');
      if (slash >= 0) {
        var seg = rest.slice(0, slash);
        addFolder(seg);
        groups[seg].count++;
        groups[seg].size += bytesText(fs[key].text || fs[key].b64 || '');
      } else {
        var f = fs[key];
        var isText = f && typeof f.text === 'string';
        files.push({
          name: rest,
          path: base + '/' + fileName,
          type: diskTypeFor(rest, isText ? 'text' : 'b64'),
          size: isText ? bytesText(f.text) : bytesText((f && f.b64) || ''),
          badge: diskBadge(rest),
          scope: 'fs', appId: id, fileName: fileName, file: f || {},
          isFolder: false, mime: (f && f.mime) || mimeFor(rest),
          editable: isText, deletable: true
        });
      }
    });
    Object.keys(fs).filter(function (k) { return k.indexOf('dir:') === 0; }).forEach(function (key) {
      var dirName = key.slice(4);
      if (dirName.indexOf(prefix) !== 0) return;
      var rest = dirName.slice(prefix.length);
      if (!rest) return;
      var slash = rest.indexOf('/');
      addFolder(slash >= 0 ? rest.slice(0, slash) : rest);
    });
    var entries = Object.keys(groups).map(function (seg) {
      var fullRel = rel ? rel + '/' + seg : seg;
      return diskFolderEntry(seg, base + '/' + fullRel, groups[seg].size, '文件夹 · ' + groups[seg].count + ' 项');
    });
    return entries.concat(files);
  }

  function diskStorageEntries(id) {
    var storage = dataScope(id);
    var base = '/应用/' + id + '/Storage';
    return Object.keys(storage).sort().map(function (key) {
      return {
        name: key,
        path: base + '/' + key,
        type: 'Storage 键',
        size: bytesText(JSON.stringify(storage[key])),
        badge: 'KV', scope: 'storage', appId: id, key: key, value: storage[key],
        isFolder: false, mime: 'application/json', editable: true, deletable: true
      };
    });
  }

  function diskApplicationEntries() {
    return diskAppIds().map(function (id) {
      var meta = diskMetaFor(id);
      var rec = appRecord(id);
      var size = (rec ? bytesText(JSON.stringify(rec)) : 0) +
        bytesText(lsGet(LS.dataPrefix + id) || '') +
        bytesText(lsGet(LS.fsPrefix + id) || '');
      return {
        name: meta.name,
        path: '/应用/' + id,
        type: '应用',
        size: size,
        badge: 'APP',
        scope: 'app', appId: id, isFolder: true
      };
    });
  }

  function diskListPath(path) {
    path = diskNorm(path);
    if (path === '/') return diskRootEntries();
    if (path === '/系统') return diskSystemEntries();
    if (path === '/原始存储') return diskRawEntries();
    if (path === '/应用') return diskApplicationEntries();
    var parts = path.split('/').filter(Boolean);
    if (parts[0] !== '应用' || !parts[1]) return [];
    var id = parts[1];
    if (parts.length === 2) return diskAppEntries(id);
    var section = parts[2];
    var rel = parts.slice(3).join('/');
    if (section === '应用包') return diskPackageEntries(id, rel);
    if (section === 'Storage') return diskStorageEntries(id);
    if (section === '虚拟文件') return diskFsEntries(id, rel);
    return [];
  }

  function diskManifestEntry(id) {
    var rec = appRecord(id);
    if (!rec) return null;
    return {
      name: 'manifest.json',
      path: '/应用/' + id + '/应用包/manifest.json',
      type: '应用清单',
      size: bytesText(JSON.stringify(rec.manifest || {})),
      badge: 'JSON', scope: 'manifest', appId: id, isFolder: false, mime: 'application/json'
    };
  }

  function collectDiskFiles() {
    var out = diskSystemEntries();
    diskAppIds().forEach(function (id) {
      var rec = appRecord(id);
      var manifest = diskManifestEntry(id);
      if (manifest) out.push(manifest);
      if (rec) {
        var base = '/应用/' + id + '/应用包';
        Object.keys(rec.files || {}).forEach(function (fileName) {
          if (fileName === 'manifest.json') return;
          var f = rec.files[fileName];
          out.push({
            name: fileName,
            path: base + '/' + fileName,
            type: diskTypeFor(fileName, f.kind),
            size: f.size || bytesText(f.value || ''),
            badge: diskBadge(fileName),
            scope: 'package', appId: id, fileName: fileName, file: f,
            isFolder: false, mime: f.mime || mimeFor(fileName)
          });
        });
      }
      var storage = dataScope(id);
      Object.keys(storage).forEach(function (key) {
        out.push({
          name: key,
          path: '/应用/' + id + '/Storage/' + key,
          type: 'Storage 键',
          size: bytesText(JSON.stringify(storage[key])),
          badge: 'KV', scope: 'storage', appId: id, key: key, value: storage[key],
          isFolder: false, editable: true, deletable: true
        });
      });
      var fs = fsScope(id);
      Object.keys(fs).filter(function (k) { return k.indexOf('file:') === 0; }).forEach(function (key) {
        var fileName = key.slice(5);
        var f = fs[key] || {};
        var isText = typeof f.text === 'string';
        out.push({
          name: fileName,
          path: '/应用/' + id + '/虚拟文件/' + fileName,
          type: diskTypeFor(fileName, isText ? 'text' : 'b64'),
          size: isText ? bytesText(f.text) : bytesText(f.b64 || ''),
          badge: diskBadge(fileName),
          scope: 'fs', appId: id, fileName: fileName, file: f,
          isFolder: false, mime: f.mime || mimeFor(fileName),
          editable: isText, deletable: true
        });
      });
    });
    return out.concat(diskRawEntries());
  }

  function diskNavigate(path) {
    state.diskPath = diskNorm(path);
    state.diskQuery = '';
    if (el.diskSearch) el.diskSearch.value = '';
    renderDisk();
    if (el.diskList) el.diskList.scrollTop = 0;
  }

  function diskIsAppPath(path) {
    var parts = String(path || '').split('/').filter(Boolean);
    return parts[0] === '应用' && parts[1];
  }

  function renderDiskTree() {
    if (!el.diskTree) return;
    var path = state.diskPath;
    var html = '';
    function row(label, target, icon, extra, active) {
      return '<button class="disk-tree-row' + (active ? ' active' : '') + '" data-disk-path="' + escapeHTML(target) + '">' +
        icon + '<span>' + escapeHTML(label) + '</span>' + (extra || '') + '</button>';
    }
    var driveIcon = '<span class="disk-tree-icon drive"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M3.5 13h17"/><circle cx="7" cy="16" r="1"/><circle cx="11" cy="16" r="1"/></svg></span>';
    var folderIcon = '<span class="disk-tree-icon folder"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M3.5 7.5A2.5 2.5 0 0 1 6 5h4l2 2h6A2.5 2.5 0 0 1 20.5 9.5v7A2.5 2.5 0 0 1 18 19H6A2.5 2.5 0 0 1 3.5 16.5Z"/></svg></span>';
    html += '<div class="disk-tree-group">磁盘</div>';
    html += row('LocalStorage', '/', driveIcon, '<em>' + formatBytes(diskUsedBytes()) + '</em>', path === '/');
    html += '<div class="disk-tree-group">文件夹</div>';
    html += row('系统', '/系统', folderIcon, '', path === '/系统');
    html += row('应用', '/应用', folderIcon, '<em>' + diskAppIds().length + '</em>', path === '/应用');
    diskAppIds().forEach(function (id) {
      var meta = diskMetaFor(id);
      var active = state.diskPath.indexOf('/应用/' + id) === 0;
      html += '<button class="disk-tree-row app' + (active ? ' active' : '') + '" data-disk-path="' + escapeHTML('/应用/' + id) + '">' +
        '<span class="disk-app-dot" style="background:' + accentFor(id) + '">' + escapeHTML(letterFor(meta.name)) + '</span>' +
        '<span>' + escapeHTML(meta.name) + '</span></button>';
    });
    html += row('原始存储', '/原始存储', folderIcon, '<em>' + lsCount() + '</em>', path === '/原始存储');
    el.diskTree.innerHTML = html;
  }

  function renderDiskBreadcrumb() {
    if (!el.diskBreadcrumb) return;
    var q = state.diskQuery.trim();
    var html = '<button class="disk-crumb" data-disk-path="/">LocalStorage</button>';
    if (q) {
      html += '<span class="disk-crumb-sep">›</span><span class="disk-crumb current">搜索 “' + escapeHTML(q) + '”</span>';
      el.diskBreadcrumb.innerHTML = html;
      return;
    }
    var path = diskNorm(state.diskPath);
    if (path !== '/') {
      var parts = path.split('/').filter(Boolean);
      var built = '';
      parts.forEach(function (seg, i) {
        built += '/' + seg;
        var label = seg;
        if (i === 1 && parts[0] === '应用') label = diskMetaFor(seg).name;
        html += '<span class="disk-crumb-sep">›</span><button class="disk-crumb" data-disk-path="' + escapeHTML(built) + '">' + escapeHTML(label) + '</button>';
      });
    }
    el.diskBreadcrumb.innerHTML = html;
  }

  function diskEntryIcon(entry) {
    if (entry.scope === 'app') {
      return '<span class="disk-app-dot" style="background:' + accentFor(entry.appId) + '">' + escapeHTML(letterFor(entry.name)) + '</span>';
    }
    if (entry.isFolder) {
      return '<span class="disk-ico folder"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M3.5 7.5A2.5 2.5 0 0 1 6 5h4l2 2h6A2.5 2.5 0 0 1 20.5 9.5v7A2.5 2.5 0 0 1 18 19H6A2.5 2.5 0 0 1 3.5 16.5Z"/></svg></span>';
    }
    return '<span class="disk-ico file" data-badge="' + escapeHTML(entry.badge || 'FILE') + '">' + escapeHTML(entry.badge || 'FILE') + '</span>';
  }

  function renderDiskList(entries) {
    if (!el.diskList) return;
    state.diskEntries = entries;
    el.diskList.hidden = entries.length === 0;
    if (el.diskEmpty) el.diskEmpty.hidden = entries.length > 0;
    if (!entries.length) {
      var q = state.diskQuery.trim();
      if (el.diskEmpty) {
        el.diskEmpty.innerHTML = '<div class="disk-empty-icon">◌</div><b>' +
          (q ? '没有匹配的文件' : '这个文件夹是空的') + '</b><span>' +
          (q ? '换个关键词，或清空搜索回到当前目录。' : '应用运行后写入的数据会出现在这里。') + '</span>';
      }
      el.diskList.innerHTML = '';
      return;
    }
    el.diskList.innerHTML = entries.map(function (entry, i) {
      var name = entry.name;
      var inSearch = !!state.diskQuery.trim();
      return '<div class="disk-row" role="button" tabindex="0" data-disk-index="' + i + '" title="' + escapeHTML(entry.path) + '">' +
        '<span class="disk-name">' + diskEntryIcon(entry) +
          '<span class="disk-name-text"><b>' + escapeHTML(name) + '</b>' +
            (inSearch ? '<small>' + escapeHTML(entry.path) + '</small>' : '') +
          '</span></span>' +
        '<span class="disk-type">' + escapeHTML(entry.type || '') + '</span>' +
        '<span class="disk-size">' + (entry.size ? formatBytes(entry.size) : '—') + '</span>' +
        '<span class="disk-trail">' + (entry.isFolder ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m9 6 6 6-6 6"/></svg>' : '') + '</span>' +
      '</div>';
    }).join('');
  }

  function renderDisk() {
    if (!el.diskList) return;
    var path, q, entries, totalFiles, used;
    try {
      path = diskNorm(state.diskPath);
      q = state.diskQuery.trim();
      var all = null;
      if (q) {
        all = collectDiskFiles();
        var ql = q.toLowerCase();
        entries = all.filter(function (e) {
          return (e.name + ' ' + e.path + ' ' + (e.type || '')).toLowerCase().indexOf(ql) >= 0;
        }).slice(0, 300);
      } else {
        entries = diskListPath(path);
        if (!entries.length && path !== '/' && path !== '/系统' && path !== '/应用' && path !== '/原始存储') {
          var parts = path.split('/').filter(Boolean);
          if (parts[0] !== '应用' || diskAppIds().indexOf(parts[1]) < 0) {
            state.diskPath = '/';
            path = '/';
            entries = diskRootEntries();
          }
        }
      }
      totalFiles = all ? all.length : collectDiskFiles().length;
      used = diskUsedBytes();
      renderDiskTree();
      renderDiskBreadcrumb();
      renderDiskList(entries);
    } catch (err) {
      console.error('renderDisk failed', err);
      if (el.diskList) el.diskList.innerHTML = '';
      if (el.diskEmpty) {
        el.diskEmpty.hidden = false;
        el.diskEmpty.innerHTML = '<div class="disk-empty-icon">◌</div><b>读取磁盘失败</b><span>' +
          escapeHTML(String(err && err.message || err)) + '</span>';
      }
      if (el.diskStatus) el.diskStatus.textContent = '读取磁盘失败';
      return;
    }
    var free = Math.max(0, CAPACITY - used);
    if (el.diskUsed) el.diskUsed.textContent = formatBytes(used);
    if (el.diskFree) el.diskFree.textContent = formatBytes(free);
    if (el.diskFiles) el.diskFiles.textContent = String(totalFiles);
    if (el.diskBar) el.diskBar.style.width = Math.min(100, used / CAPACITY * 100) + '%';
    if (el.diskCount) el.diskCount.textContent = totalFiles > 99 ? '99+' : String(totalFiles);
    if (el.diskStatus) {
      el.diskStatus.textContent = entries.length + ' 个项目 · 已用 ' + formatBytes(used) + ' · 可用 ' + formatBytes(free);
    }
    if (el.diskSearch && el.diskSearch.value !== state.diskQuery) el.diskSearch.value = state.diskQuery;
  }

  function diskEntryText(entry) {
    if (entry.scope === 'system' || entry.scope === 'raw') return lsGet(entry.key) || '';
    if (entry.scope === 'manifest') {
      var rec = appRecord(entry.appId);
      return JSON.stringify(rec ? rec.manifest : {}, null, 2);
    }
    if (entry.scope === 'storage') return JSON.stringify(entry.value, null, 2);
    if (entry.scope === 'package') return entry.file && entry.file.kind === 'text' ? entry.file.value : '';
    if (entry.scope === 'fs') return entry.file && typeof entry.file.text === 'string' ? entry.file.text : '';
    return '';
  }

  function diskEntryB64(entry) {
    if (entry.scope === 'package' && entry.file && entry.file.kind === 'b64') return entry.file.value;
    if (entry.scope === 'fs' && entry.file && typeof entry.file.b64 === 'string') return entry.file.b64;
    return '';
  }

  function diskEntryMime(entry) {
    if (entry.scope === 'system' || entry.scope === 'raw' || entry.scope === 'manifest' || entry.scope === 'storage') {
      return 'application/json';
    }
    return entry.mime || mimeFor(entry.name || '');
  }

  function diskB64ToBlob(b64, mime) {
    try {
      var bin = atob(String(b64 || '').replace(/\s+/g, ''));
      var u8 = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
      return new Blob([u8], { type: mime || 'application/octet-stream' });
    } catch (e) {
      return new Blob([b64 || ''], { type: 'text/plain' });
    }
  }

  function downloadDiskEntry(entry) {
    if (!entry) return;
    var b64 = diskEntryB64(entry);
    var blob;
    if (b64) {
      blob = diskB64ToBlob(b64, diskEntryMime(entry));
    } else {
      var text = diskEntryText(entry);
      blob = new Blob([text], { type: diskEntryMime(entry) === 'application/json' ? 'application/json' : 'text/plain' });
    }
    downloadBlob(blob, String(entry.name || 'localstorage-file').split('/').pop());
    toast('已开始下载', 1400);
  }

  function diskEntryPreviewHTML(entry) {
    var b64 = diskEntryB64(entry);
    var mime = diskEntryMime(entry);
    if (b64 && /^image\//.test(mime)) {
      return '<div class="ql-image"><img src="data:' + mime + ';base64,' + b64 + '" alt=""></div>';
    }
    if (b64 && /^audio\//.test(mime)) {
      return '<audio class="ql-audio" controls src="data:' + mime + ';base64,' + b64 + '"></audio>';
    }
    if (b64 && /^video\//.test(mime)) {
      return '<video class="ql-video" controls src="data:' + mime + ';base64,' + b64 + '"></video>';
    }
    if (b64) {
      return '<div class="ql-binary"><div class="ql-binary-icon">◇</div><b>二进制文件</b><span>' +
        formatBytes(entry.size || 0) + ' · ' + escapeHTML(mime) + '</span>' +
        '<p>浏览器无法直接预览这个格式，可以下载到本机查看。</p></div>';
    }
    var text = diskEntryText(entry);
    if (text == null) text = '';
    var cut = text.length > 80000;
    if (cut) text = text.slice(0, 80000);
    return (cut ? '<div class="ql-note">文件较大，仅显示前 80 KB。</div>' : '') +
      '<pre class="ql-text">' + escapeHTML(text) + '</pre>';
  }

  function openDiskPreview(entry) {
    if (!entry) return;
    var mask = document.createElement('div');
    mask.className = 'modal-mask ql-mask';
    mask.innerHTML =
      '<div class="modal-card ql-card">' +
        '<div class="ql-head">' +
          '<div class="ql-icon">' + diskEntryIcon(entry) + '</div>' +
          '<div class="ql-title"><b>' + escapeHTML(entry.name) + '</b><span>' + escapeHTML(entry.path) + ' · ' + formatBytes(entry.size || 0) + '</span></div>' +
          '<button class="ql-close" data-ql="close" title="关闭">×</button>' +
        '</div>' +
        '<div class="ql-body">' + diskEntryPreviewHTML(entry) + '</div>' +
        '<div class="ql-foot">' +
          '<span class="ql-kind">' + escapeHTML(entry.type || '文件') + '</span>' +
          '<div class="ql-actions">' +
            (entry.editable ? '<button class="ql-btn" data-ql="edit">编辑</button>' : '') +
            (entry.deletable ? '<button class="ql-btn danger" data-ql="delete">删除</button>' : '') +
            '<button class="ql-btn" data-ql="download">下载</button>' +
            '<button class="ql-btn primary" data-ql="close">完成</button>' +
          '</div>' +
        '</div>' +
      '</div>';
    el.modalRoot.appendChild(mask);
    var modal = { close: close };
    state.modals.push(modal);
    function close() {
      state.modals = state.modals.filter(function (m) { return m !== modal; });
      mask.remove();
    }
    mask.addEventListener('click', async function (e) {
      if (e.target === mask) { close(); return; }
      var button = e.target.closest ? e.target.closest('[data-ql]') : null;
      if (!button) return;
      var act = button.getAttribute('data-ql');
      if (act === 'close') { close(); return; }
      if (act === 'download') { downloadDiskEntry(entry); return; }
      if (act === 'edit') {
        if (entry.scope === 'storage') {
          close();
          openStorageEditor(entry.appId, entry.key, JSON.stringify(entry.value, null, 2), false, function () {
            renderDisk(); renderSettings(); renderStorage();
          });
        } else if (entry.scope === 'fs') {
          close();
          openFileEditor(entry.appId, entry.fileName, entry.file.text, function () {
            renderDisk(); renderSettings(); renderStorage();
          });
        }
        return;
      }
      if (act === 'delete') {
        var ok = await uiModal({
          title: '删除「' + entry.name + '」？',
          content: entry.scope === 'storage' ? '这条 Storage 键会被永久删除。' : '这个虚拟文件会被永久删除。',
          confirmText: '删除', danger: true
        });
        if (!ok) return;
        if (entry.scope === 'storage') {
          var storage = dataScope(entry.appId);
          delete storage[entry.key];
          saveDataScope(entry.appId, storage);
        } else if (entry.scope === 'fs') {
          var fs = fsScope(entry.appId);
          delete fs['file:' + entry.fileName];
          saveFs(entry.appId, fs);
        }
        close();
        renderDisk(); renderSettings(); renderStorage();
        toast('已删除', 1400);
      }
    });
  }

  function openDiskEntry(entry) {
    if (!entry) return;
    if (entry.isFolder) diskNavigate(entry.path);
    else openDiskPreview(entry);
  }

  /* ---------------- 视图 ---------------- */

  var VIEW_META = {
    apps: { title: '应用库', sub: '浏览器里的 Kinter，开箱即用，不依赖设备。' },
    disk: { title: '文件浏览器', sub: '把 LocalStorage 当作一块本地磁盘，浏览全部系统、应用与数据文件。' },
    import: { title: '导入小程序', sub: 'ZIP 在本地解压，文件只写入这台设备的 LocalStorage。' },
    settings: { title: '设置与数据', sub: '管理本地应用、存储、备份和浏览器权限。' }
  };

  function showView(name) {
    name = VIEW_META[name] ? name : 'apps';
    ['apps', 'disk', 'import', 'settings'].forEach(function (v) {
      var node = $('view' + v.charAt(0).toUpperCase() + v.slice(1));
      if (node) node.hidden = v !== name;
    });
    document.querySelectorAll('.nav-item').forEach(function (b) {
      b.classList.toggle('active', b.getAttribute('data-nav') === name);
    });
    if (el.pageTitle) el.pageTitle.textContent = VIEW_META[name].title;
    if (el.pageSub) el.pageSub.textContent = VIEW_META[name].sub;
    var topSearch = document.querySelector('.search');
    if (topSearch) topSearch.style.display = name === 'disk' ? 'none' : '';
    if (name === 'settings') renderSettings();
    if (name === 'apps') renderApps();
    if (name === 'disk') renderDisk();
    if (name !== 'apps' && el.searchInput) el.searchInput.value = '';
    state.query = '';
  }

  /* ---------------- 弹层 ---------------- */

  function toast(text, duration) {
    if (!el.toastRoot) return;
    var node = document.createElement('div');
    node.className = 'toast';
    node.textContent = text;
    el.toastRoot.appendChild(node);
    setTimeout(function () {
      node.classList.add('out');
      setTimeout(function () { node.remove(); }, 260);
    }, Math.max(900, Number(duration) || 1800));
  }

  function uiModal(opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var mask = document.createElement('div');
      mask.className = 'modal-mask';
      var actions = opts.cancelText === null
        ? '<button class="primary" data-m="ok">' + escapeHTML(opts.confirmText || '知道了') + '</button>'
        : '<button data-m="cancel">' + escapeHTML(opts.cancelText || '取消') + '</button>' +
          '<button class="primary' + (opts.danger ? ' danger-btn' : '') + '" data-m="ok">' + escapeHTML(opts.confirmText || '确定') + '</button>';
      mask.innerHTML = '<div class="modal-card">' +
        '<h2>' + escapeHTML(opts.title || '提示') + '</h2>' +
        (opts.content ? '<p>' + escapeHTML(opts.content) + '</p>' : '') +
        '<div class="modal-actions">' + actions + '</div>' +
      '</div>';
      el.modalRoot.appendChild(mask);
      var entry = { close: done };
      state.modals.push(entry);
      function done(value) {
        state.modals = state.modals.filter(function (m) { return m !== entry; });
        mask.remove();
        resolve(value);
      }
      mask.addEventListener('click', function (e) {
        var b = e.target.closest ? e.target.closest('[data-m]') : null;
        if (!b) return;
        done(b.getAttribute('data-m') === 'ok');
      });
    });
  }

  function uiActionSheet(items, title) {
    return new Promise(function (resolve) {
      var mask = document.createElement('div');
      mask.className = 'modal-mask';
      mask.innerHTML = '<div class="modal-card">' +
        (title ? '<h2>' + escapeHTML(title) + '</h2>' : '') +
        '<div class="action-list">' + items.map(function (t, i) {
          return '<button data-i="' + i + '">' + escapeHTML(t) + '</button>';
        }).join('') + '</div>' +
        '<div class="modal-actions"><button data-m="cancel">取消</button></div>' +
      '</div>';
      el.modalRoot.appendChild(mask);
      var entry = { close: done };
      state.modals.push(entry);
      function done(value) {
        state.modals = state.modals.filter(function (m) { return m !== entry; });
        mask.remove();
        resolve(value);
      }
      mask.addEventListener('click', function (e) {
        var b = e.target.closest ? e.target.closest('[data-i],[data-m]') : null;
        if (!b) return;
        if (b.hasAttribute('data-i')) done(Number(b.getAttribute('data-i')));
        else done(-1);
      });
    });
  }

  function dismissModals() {
    var list = state.modals.slice();
    list.forEach(function (m) {
      try { m.close(false); } catch (e) {}
    });
    state.modals = [];
  }

  /* ---------------- 运行器 ---------------- */

  function runningRecord() {
    return state.running ? appRecord(state.running.appId) : null;
  }

  function installFrameLogger() {
    var frame = el.appFrame;
    if (!frame) return;
    try {
      var doc = frame.contentDocument;
      if (!doc || !doc.documentElement) return;
      if (doc.documentElement.getAttribute('data-kfw-logger') === '1') return;
      var script = doc.createElement('script');
      script.textContent = FRAME_LOGGER;
      (doc.head || doc.documentElement).appendChild(script);
    } catch (e) {}
  }

  function addRuntimeLog(level, message) {
    var safeLevel = ['log', 'info', 'warn', 'error'].indexOf(level) >= 0 ? level : 'log';
    var text = String(message == null ? '' : message);
    if (text.length > 4000) text = text.slice(0, 4000) + '…';
    state.logs.push({
      level: safeLevel,
      time: new Date().toLocaleTimeString('zh-CN', { hour12: false }),
      text: text
    });
    if (state.logs.length > 240) state.logs = state.logs.slice(-240);
    if (!state.consoleOpen) state.unreadLogs += 1;
    renderConsole();
  }

  function renderConsole() {
    if (!el.consoleOutput) return;
    el.consoleOutput.innerHTML = state.logs.length ? state.logs.map(function (l) {
      return '<span class="' + escapeHTML(l.level) + '">[' + escapeHTML(l.time) + '] ' + escapeHTML(l.text) + '</span>';
    }).join('\n') : '等待小程序输出…';
    if (el.consoleCount) el.consoleCount.textContent = String(state.logs.length);
    if (el.consoleBadge) {
      el.consoleBadge.hidden = state.consoleOpen || state.unreadLogs === 0;
      el.consoleBadge.textContent = String(Math.min(99, state.unreadLogs));
    }
    el.consoleOutput.scrollTop = el.consoleOutput.scrollHeight;
  }

  function toggleConsole(force) {
    if (!el.runnerConsole) return;
    var open = typeof force === 'boolean' ? force : el.runnerConsole.hidden;
    el.runnerConsole.hidden = !open;
    state.consoleOpen = open;
    if (open) state.unreadLogs = 0;
    renderConsole();
  }

  function resetConsole() {
    state.logs = [];
    state.unreadLogs = 0;
    state.consoleOpen = false;
    if (el.runnerConsole) el.runnerConsole.hidden = true;
    renderConsole();
  }

  function openApp(id) {
    var rec = appRecord(id);
    var meta = state.apps.filter(function (a) { return a.appId === id; })[0];
    if (!rec) { toast('应用不存在，请重新导入', 2000); return; }
    var entry = resolvePagePath(rec, rec.entry || (rec.pages && rec.pages[0]) || 'index');
    if (!entry) { toast('应用缺少入口页面', 2000); return; }
    state.running = { appId: id, stack: [entry], page: entry, rec: rec };
    resetConsole();
    if (el.runner) el.runner.hidden = false;
    if (el.runnerName) el.runnerName.textContent = rec.name || meta && meta.name || id;
    if (el.runnerIcon) {
      var runIcon = safeIcon(rec.icon);
      el.runnerIcon.textContent = letterFor(rec.name || id);
      el.runnerIcon.style.backgroundImage = runIcon ? 'url(\'' + runIcon.replace(/'/g, '%27') + '\')' : '';
      el.runnerIcon.style.background = runIcon ? '' : 'linear-gradient(145deg,' + accentFor(id) + ',' + shade(accentFor(id), -24) + ')';
    }
    setRunnerMeta(entry, 1);
    loadPage(entry, 'replace');
  }

  function stopNetworkWatchInternal() {
    if (netHandler) {
      window.removeEventListener('online', netHandler);
      window.removeEventListener('offline', netHandler);
      netHandler = null;
    }
  }

  function releaseRunnerResources() {
    // 录音：停止轨道与编码器
    Object.keys(state.recorders).forEach(function (id) {
      var it = state.recorders[id];
      try { if (it.stream) it.stream.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
      try { if (it.rec && it.rec.state !== 'inactive') it.rec.stop(); } catch (e) {}
    });
    state.recorders = {};
    // 音频 / 音乐元素
    Object.keys(state.audio).forEach(function (id) {
      try { state.audio[id].pause(); state.audio[id].removeAttribute('src'); state.audio[id].load(); } catch (e) {}
    });
    Object.keys(state.music).forEach(function (id) {
      try { state.music[id].pause(); state.music[id].removeAttribute('src'); state.music[id].load(); } catch (e) {}
    });
    state.audio = {};
    state.music = {};
    stopNetworkWatchInternal();
    stopWatchers();
    closeSocket();
    if (wakeLock) { try { wakeLock.release(); } catch (e) {} wakeLock = null; }
    try { if (window.speechSynthesis) speechSynthesis.cancel(); } catch (e) {}
    state.blobUrls.forEach(function (u) { try { URL.revokeObjectURL(u); } catch (e) {} });
    state.blobUrls = [];
  }

  function closeRunner() {
    state.running = null;
    dismissModals();
    releaseRunnerResources();
    if (el.runner) el.runner.hidden = true;
    if (el.appFrame) el.appFrame.srcdoc = '<!doctype html><html><body></body></html>';
    resetConsole();
    if (el.runnerMeta) el.runnerMeta.textContent = 'Web Runtime';
  }

  function setRunnerMeta(page, index) {
    if (!el.runnerMeta) return;
    var rec = runningRecord();
    var total = state.running ? state.running.stack.length : 0;
    el.runnerMeta.textContent = (rec ? rec.name : '') + ' · ' + page + (total > 1 ? ' · 第 ' + index + '/' + total + ' 层' : ' · Web Runtime');
  }

  function resolvePagePath(rec, page) {
    if (!rec || !rec.files) return '';
    var p = String(page || '').replace(/^\.?\//, '').replace(/\\/g, '/');
    var cands = [p];
    if (!/\.(html?|ktml)$/i.test(p)) {
      cands.push(p + '.html', p + '.ktml');
    }
    cands.push('index.html', 'index.ktml', 'pages/index/index.html', 'pages/index/index.ktml');
    for (var i = 0; i < cands.length; i++) {
      var f = rec.files[normPath(cands[i])];
      if (f && f.kind === 'text') return normPath(cands[i]);
    }
    var keys = Object.keys(rec.files);
    for (var j = 0; j < keys.length; j++) {
      if (/\.(html|ktml)$/i.test(keys[j])) return keys[j];
    }
    return '';
  }

  function loadPage(page, method) {
    if (!state.running) return;
    var rec = state.running.rec || runningRecord();
    var entry = resolvePagePath(rec, page);
    if (!entry) { toast('页面不存在：' + page, 2000); return; }
    state.running.page = entry;
    var idx = state.running.stack.indexOf(entry) + 1;
    if (method !== 'back' && method !== 'replace') idx = state.running.stack.length;
    setRunnerMeta(entry, idx);

    var file = rec.files[entry];
    var source = file.value;
    var html;
    if (/\.ktml$/i.test(entry)) {
      try {
        html = KTML.toStandaloneHTML(source);
      } catch (e) {
        console.error('KTML 编译失败', e);
        html = '<!doctype html><html><body><h2>KTML 编译失败</h2><p>' + escapeHTML(e.message) + '</p></body></html>';
      }
    } else {
      html = source;
    }
    var doc = buildDocument(rec, entry, html);
    if (el.appFrame) el.appFrame.srcdoc = doc;
    addRuntimeLog('info', 'Loaded ' + entry);
  }

  function buildDocument(rec, pagePath, html) {
    html = String(html || '');
    html = html.replace(/<meta[^>]+http-equiv=["']?content-security-policy["']?[^>]*>/gi, '');
    html = rewriteAssets(html, dirname(pagePath), rec);
    var inject = '<script>' + FRAME_LOGGER + '</script><meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">' +
      '<base href="' + BASE_URL + '">' +
      '<script>window.__KFW_APP_ID__=' + JSON.stringify(rec.appId) + ';window.__KFW_APP_NAME__=' + JSON.stringify(rec.name) + ';</script>' +
      '<script src="' + BASE_URL + 'bridge.js?v=20261114b"></script>' +
      '<script src="' + BASE_URL + 'wx.js?v=20261114b"></script>' +
      '<script src="' + BASE_URL + 'ktml.js?v=20261114b"></script>';
    if (/<head[^>]*>/i.test(html)) {
      html = html.replace(/<head[^>]*>/i, function (m) { return m + inject; });
    } else {
      var doctype = '';
      if (/^\s*<!doctype/i.test(html)) {
        html = html.replace(/^\s*<!doctype[^>]*>/i, function (m) { doctype = m; return ''; });
      }
      html = doctype + '<html><head>' + inject + '</head><body>' + html + '</body></html>';
    }
    return html;
  }

  function rewriteAssets(html, dir, rec) {
    html = html.replace(/\s(src|href|poster)\s*=\s*("([^"]*)"|'([^']*)')/gi, function (m, attr, quoted, dq, sq) {
      var val = dq != null ? dq : sq;
      var replacement = assetDataURL(rec, dir, val);
      if (!replacement) return m;
      return ' ' + attr + '="' + replacement + '"';
    });
    html = html.replace(/url\(\s*('([^']*)'|"([^"]*)"|([^)'"]*))\s*\)/gi, function (m, wrapped, sq, dq, bare) {
      var val = sq != null ? sq : (dq != null ? dq : bare);
      var replacement = assetDataURL(rec, dir, val);
      return replacement ? 'url("' + replacement + '")' : m;
    });
    return html;
  }

  function assetDataURL(rec, dir, raw) {
    var v = String(raw || '').trim();
    if (!v || /^(data:|https?:|blob:|#|mailto:|tel:|sms:|javascript:|about:)/i.test(v)) return '';
    var clean = v.split('#')[0].split('?')[0];
    if (!clean) return '';
    var path = clean.charAt(0) === '/' ? normPath(clean.slice(1)) : normPath((dir ? dir + '/' : '') + clean);
    var f = rec.files[path];
    if (!f) return '';
    if (f.kind === 'text') {
      return 'data:' + mimeFor(path) + ';charset=utf-8,' + encodeURIComponent(f.value);
    }
    return 'data:' + (f.mime || mimeFor(path)) + ';base64,' + f.value;
  }

  /* ---------------- 父页对外桥 ---------------- */

  function emitApp(event, data) {
    if (!el.appFrame) return;
    var payload = { type: 'kfw-event', event: event, data: data };
    try {
      var w = el.appFrame.contentWindow;
      // 子帧为不透明源，targetOrigin 无法写具体 URL，故用 '*'；接收方在 bridge.js/wx.js 校验 e.source === parent
      if (w) w.postMessage(payload, '*');
      else pushQueued(payload);
    } catch (e) { pushQueued(payload); }
  }

  function pushQueued(payload) {
    state.eventsQueued.push(payload);
    if (state.eventsQueued.length > 100) state.eventsQueued.splice(0, state.eventsQueued.length - 100);
  }

  function flushEvents() {
    if (!state.eventsQueued.length) return;
    try {
      var w = el.appFrame.contentWindow;
      if (w) {
        var list = state.eventsQueued.slice();
        state.eventsQueued = [];
        list.forEach(function (p) { w.postMessage(p, '*'); });
      }
    } catch (e) {}
  }

  function navDefer(fn) { setTimeout(fn, 30); }

  function bridgeError(code, message) {
    return { code: code, message: message };
  }

  // 防御性网络边界：禁止回连 Kinter iOS 宿主端口与 /api 接口
  function isBlockedUrl(url) {
    var u = String(url || '');
    if (!u) return false;
    if (/^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]):18765\b/i.test(u)) return true;
    try {
      var parsed = new URL(u, location.href);
      if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
        if (parsed.hostname === '127.0.0.1' && parsed.port === '18765') return true;
        if (/^\/api(\/|$)/.test(parsed.pathname)) return true;
      }
    } catch (e) {}
    return false;
  }

  function allowedHttpUrl(url) { return /^https?:\/\//i.test(String(url || '')); }
  function allowedWsUrl(url) { return /^wss?:\/\//i.test(String(url || '')); }

  function handleIncomingBridge(e) {
    var payload = e.data || {};
    var callbackId = payload.callbackId;
    if (!callbackId) return;
    var win = el.appFrame && el.appFrame.contentWindow;
    // 二次来源校验：监听处已过滤，这里再严格绑定当前运行帧；帧已关闭/切换则丢弃
    if (!win || e.source !== win) return;
    function reply(ok, data, error) {
      try {
        // 子帧为不透明源，targetOrigin 无法写具体 URL，故用 '*'；来源已由上面的 event.source 严格绑定
        if (win) win.postMessage({ type: 'kfw-bridge-reply', callbackId: callbackId, ok: !!ok, data: data == null ? {} : data, error: error }, '*');
      } catch (err) {}
    }
    Promise.resolve().then(function () {
      return bridgeCall(payload.appId, payload.module, payload.method, payload.params || {});
    }).then(function (data) {
      reply(true, data, null);
    }).catch(function (err) {
      reply(false, null, err && err.code ? err : { code: 'provider_error', message: String((err && err.message) || err) });
    });
  }

  async function bridgeCall(appId, module, method, params) {
    params = params || {};
    if (!state.running || String(appId) !== String(state.running.appId)) {
      throw bridgeError('app_mismatch', '小程序未在运行');
    }
    var rec = state.running.rec || runningRecord();
    var rid = state.running.appId;
    switch (module) {
      case 'popup':
        return handlePopup(method, params);
      case 'router':
        return handleRouter(method, params);
      case 'storage':
        return handleStorage(rid, method, params);
      case 'store':
        return handleStore(rid, method, params);
      case 'files':
        return handleFiles(rid, method, params);
      case 'http':
        return handleHTTP(method, params);
      case 'upload':
        return handleUpload(method, params);
      case 'websocket':
        return handleSocket(method, params);
      case 'networkWatch':
        return handleNetworkWatch(method, params);
      case 'camera':
        return handleCamera(method, params);
      case 'photo':
        return handlePhoto(method, params);
      case 'microphone':
        return handleMicrophone(rid, method, params);
      case 'videoRecord':
        return handleVideoRecord(method, params);
      case 'image':
        return handleImage(method, params);
      case 'savePhoto':
        return handleSavePhoto(method, params);
      case 'audio':
        return handleAudio(rid, method, params);
      case 'music':
        return handleMusic(rid, method, params);
      case 'tts':
        return handleTTS(method, params);
      case 'qrScan':
        return handleQRScan(method, params);
      case 'location':
        return handleLocation(method, params);
      case 'locationWatch':
        return handleLocationWatch(rid, method, params);
      case 'deviceInfo':
        return handleDeviceInfo(method, params);
      case 'battery':
        return handleBattery(method, params);
      case 'network':
        return handleNetwork(method, params);
      case 'motion':
        return handleMotion(method, params);
      case 'clipboard':
        return handleClipboard(method, params);
      case 'clipboardImage':
        return handleClipboardImage(method, params);
      case 'vibrate':
        return handleVibrate(method, params);
      case 'screenAwake':
        return handleScreenAwake(method, params);
      case 'notification':
        return handleNotification(method, params);
      case 'permission':
        return handlePermission(method, params);
      case 'share':
        return handleShare(method, params);
      case 'openURL':
        return handleOpenURL(method, params);
      case 'communication':
        return handleCommunication(method, params);
      case 'brightness':
      case 'contacts':
      case 'calendar':
      case 'reminder':
      case 'speech':
      case 'health':
      case 'bluetooth':
      case 'bluetoothScan':
      case 'biometric':
      case 'ocr':
      case 'qrGenerate':
        throw bridgeError('unsupported', '当前浏览器宿主未实现该能力');
      default:
        throw bridgeError('method_not_found', '未知能力：' + module + '.' + method);
    }
  }

  /* ---------------- 弹窗/路由实现 ---------------- */

  async function handlePopup(method, p) {
    if (method === 'toast') {
      toast(String(p.title || p.message || ''), Number(p.duration) || 1800);
      return { ok: true };
    }
    if (method === 'modal') {
      var ok = await uiModal({
        title: p.title || '提示',
        content: p.content || p.message || '',
        confirmText: p.confirmText || '确定',
        cancelText: p.showCancel === false ? null : (p.cancelText || '取消')
      });
      return { confirm: ok, cancel: !ok };
    }
    if (method === 'actionSheet') {
      var items = Array.isArray(p.itemList) ? p.itemList : (Array.isArray(p.items) ? p.items : []);
      var idx = await uiActionSheet(items, p.title || '请选择');
      return { index: idx, cancelled: idx < 0, tapIndex: idx };
    }
    if (method === 'dismissAll') {
      dismissModals();
      return { ok: true };
    }
    throw bridgeError('method_not_found', 'popup.' + method);
  }

  function handleRouter(method, p) {
    if (!state.running) throw bridgeError('no_app', '没有正在运行的小程序');
    if (method === 'getStack') {
      return { stack: state.running.stack.map(function (page, i) {
        return { page: page, index: i };
      }) };
    }
    if (method === 'navigateBack') {
      var delta = Math.max(1, Number(p.delta) || 1);
      var stack = state.running.stack;
      if (stack.length <= 1) {
        navDefer(closeRunner);
        return { ok: true };
      }
      stack.splice(Math.max(1, stack.length - delta), delta);
      var target = stack[stack.length - 1];
      navDefer(function () { loadPage(target, 'back'); });
      return { ok: true };
    }
    var url = p.url || p.path || p.page;
    if (!url) throw bridgeError('invalid_params', 'url 必填');
    var entry = resolvePagePath(state.running.rec || runningRecord(), url);
    if (!entry) throw bridgeError('page_not_found', '页面不存在：' + url);
    if (method === 'navigateTo') {
      state.running.stack.push(entry);
      navDefer(function () { loadPage(entry, 'push'); });
    } else if (method === 'redirectTo') {
      state.running.stack[state.running.stack.length - 1] = entry;
      navDefer(function () { loadPage(entry, 'replace'); });
    } else if (method === 'reLaunch') {
      state.running.stack = [entry];
      navDefer(function () { loadPage(entry, 'replace'); });
    } else {
      throw bridgeError('method_not_found', 'router.' + method);
    }
    return { ok: true };
  }

  /* ---------------- 存储/文件 ---------------- */

  function dataScope(id) {
    return readJSON(LS.dataPrefix + id, {});
  }

  function saveDataScope(id, obj) {
    writeJSON(LS.dataPrefix + id, obj);
  }

  function handleStorage(id, method, p) {
    var key = String(p.key || '');
    if (!key) throw bridgeError('invalid_params', 'key 必填');
    if (method === 'set') {
      var data = dataScope(id);
      if (p.data === undefined) throw bridgeError('invalid_params', 'data 必填');
      if (bytesText(JSON.stringify(p.data)) > 256 * 1024) throw bridgeError('invalid_params', '单个值超过 256KB');
      data[key] = p.data;
      saveDataScope(id, data);
      return { ok: true };
    }
    if (method === 'get') {
      return { data: Object.prototype.hasOwnProperty.call(dataScope(id), key) ? dataScope(id)[key] : null };
    }
    if (method === 'remove') {
      var d = dataScope(id);
      delete d[key];
      saveDataScope(id, d);
      return { ok: true };
    }
    if (method === 'clear') {
      saveDataScope(id, {});
      return { ok: true };
    }
    throw bridgeError('method_not_found', 'storage.' + method);
  }

  var globalStores = {};
  function handleStore(id, method, p) {
    if (!globalStores[id]) globalStores[id] = {};
    var store = globalStores[id];
    var key = String(p.key || '');
    if (method === 'set') {
      if (!key) throw bridgeError('invalid_params', 'key 必填');
      store[key] = p.data;
      return { ok: true };
    }
    if (method === 'get') return { data: Object.prototype.hasOwnProperty.call(store, key) ? store[key] : null };
    if (method === 'remove') { delete store[key]; return { ok: true }; }
    if (method === 'clear') { globalStores[id] = {}; return { ok: true }; }
    if (method === 'all') return { data: store };
    throw bridgeError('method_not_found', 'store.' + method);
  }

  function fsScope(id) {
    return readJSON(LS.fsPrefix + id, {});
  }
  function saveFs(id, obj) { writeJSON(LS.fsPrefix + id, obj); }
  function normalizeVirtual(path) {
    var p = String(path || '').replace(/^kinter:\/\//, '').replace(/^file:\/\//, '');
    p = p.replace(/^\/*/, '');
    var slash = p.indexOf('/');
    if (slash >= 0 && p.slice(0, slash) === state.running.appId) p = p.slice(slash + 1);
    if (/[?*"<>|:\\]/.test(p)) throw bridgeError('invalid_params', '路径含非法字符');
    var segs = p.split('/').filter(Boolean);
    for (var i = 0; i < segs.length; i++) {
      if (segs[i] === '..' || segs[i] === '.') throw bridgeError('invalid_params', '拒绝路径穿越：' + p);
    }
    return segs.join('/');
  }

  function handleFiles(id, method, p) {
    var fs = fsScope(id);
    if (method === 'info') {
      return { path: 'kinter://' + id + '/data', appId: id, virtual: true, storage: 'localStorage' };
    }
    if (method === 'mkdir') {
      var dir = normalizeVirtual(p.path || p.dirPath || '');
      fs['dir:' + dir] = true;
      saveFs(id, fs);
      return { ok: true, path: 'kinter://' + id + '/data/' + dir };
    }
    if (method === 'write') {
      var wpath = normalizeVirtual(p.path || p.filePath || p.file);
      if (!wpath) throw bridgeError('invalid_params', 'path 必填');
      var content = p.data != null ? p.data : (p.content != null ? p.content : '');
      if (String(content).length > 2 * 1024 * 1024) throw bridgeError('invalid_params', '单个虚拟文件超过 2 MB');
      if (p.base64 || p.encoding === 'base64') fs['file:' + wpath] = { b64: String(content), encoding: 'base64' };
      else fs['file:' + wpath] = { text: String(content) };
      saveFs(id, fs);
      return { ok: true, path: 'kinter://' + id + '/data/' + wpath };
    }
    if (method === 'read') {
      var rpath = normalizeVirtual(p.path || p.filePath || p.file);
      var f = fs['file:' + rpath];
      if (!f) throw bridgeError('not_found', '文件不存在：' + rpath);
      return { data: f.encoding === 'base64' ? f.b64 : f.text, encoding: f.encoding || 'utf8', path: 'kinter://' + id + '/data/' + rpath };
    }
    if (method === 'remove') {
      var del = normalizeVirtual(p.path || p.filePath || p.file);
      delete fs['file:' + del];
      saveFs(id, fs);
      return { ok: true };
    }
    if (method === 'listDir' || method === 'list') {
      var dir2 = normalizeVirtual(p.path || p.dirPath || '');
      var files = Object.keys(fs).filter(function (k) { return k.indexOf('file:') === 0; }).map(function (k) { return k.slice(5); });
      if (dir2) files = files.filter(function (f) { return f.indexOf(dir2 + '/') === 0; });
      return { files: files, path: 'kinter://' + id + '/data/' + dir2 };
    }
    throw bridgeError('method_not_found', 'files.' + method);
  }

  /* ---------------- 网络 ---------------- */

  async function handleHTTP(method, p) {
    if (method !== 'request') throw bridgeError('method_not_found', 'http.' + method);
    var url = String(p.url || '');
    if (!url) throw bridgeError('invalid_params', 'url 必填');
    if (!allowedHttpUrl(url)) throw bridgeError('invalid_params', '仅支持 http/https 地址');
    if (isBlockedUrl(url)) throw bridgeError('blocked', '该地址被运行时禁止访问');
    var opt = {
      method: p.method || 'GET',
      headers: p.headers || {},
      body: p.body != null ? p.body : undefined
    };
    if (p.timeout) {
      opt.signal = AbortSignal.timeout ? AbortSignal.timeout(Math.min(60000, Math.max(1000, p.timeout * 1000))) : undefined;
    }
    var res = await fetch(url, opt);
    var text = await res.text();
    var headers = {};
    res.headers.forEach(function (v, k) { headers[k] = v; });
    return { status: res.status, body: text, headers: headers };
  }

  async function handleUpload(method, p) {
    if (method !== 'upload') throw bridgeError('method_not_found', 'upload.' + method);
    var url = String(p.url || '');
    if (!url) throw bridgeError('invalid_params', 'url 必填');
    if (!allowedHttpUrl(url)) throw bridgeError('invalid_params', '仅支持 http/https 地址');
    if (isBlockedUrl(url)) throw bridgeError('blocked', '该地址被运行时禁止访问');
    var fd = new FormData();
    if (p.formData && typeof p.formData === 'object') {
      Object.keys(p.formData).forEach(function (k) { fd.append(k, String(p.formData[k])); });
    }
    if (p.filePath) {
      var blob = await urlToBlob(p.filePath);
      fd.append(p.name || 'file', blob, p.fileName || 'upload.bin');
    }
    var res = await fetch(url, { method: 'POST', body: fd, headers: p.headers || {} });
    return { status: res.status, body: await res.text() };
  }

  async function urlToBlob(url) {
    if (/^data:/i.test(url)) {
      var r = await fetch(url);
      return await r.blob();
    }
    if (!allowedHttpUrl(url)) throw bridgeError('invalid_params', '仅支持 http/https 或 data: 地址');
    if (isBlockedUrl(url)) throw bridgeError('blocked', '该地址被运行时禁止访问');
    var r2 = await fetch(url);
    return await r2.blob();
  }

  function closeSocket() {
    if (state.socket) {
      try { state.socket.close(); } catch (e) {}
      state.socket = null;
    }
  }

  function handleSocket(method, p) {
    if (method === 'connect') {
      closeSocket();
      var url = String(p.url || '');
      if (!url) throw bridgeError('invalid_params', 'url 必填');
      if (!allowedWsUrl(url)) throw bridgeError('invalid_params', '仅支持 ws/wss 地址');
      if (/^wss?:\/\/(127\.0\.0\.1|localhost|\[::1\]):18765\b/i.test(url)) throw bridgeError('blocked', '该地址被运行时禁止访问');
      var ws = new WebSocket(url);
      state.socket = ws;
      ws.onopen = function () { emitApp('websocket.open', { url: url }); };
      ws.onmessage = function (e) {
        if (typeof e.data === 'string') emitApp('websocket.message', { data: e.data });
        else emitApp('websocket.message', { data: '二进制消息暂不支持', binary: true });
      };
      ws.onerror = function () { emitApp('websocket.error', { message: 'WebSocket 连接错误' }); };
      ws.onclose = function (e) { emitApp('websocket.close', { code: e.code, reason: e.reason }); state.socket = null; };
      return { ok: true, url: url };
    }
    if (method === 'send') {
      if (!state.socket || state.socket.readyState !== 1) throw bridgeError('not_open', 'WebSocket 未连接');
      state.socket.send(String(p.data == null ? '' : p.data));
      return { ok: true };
    }
    if (method === 'close') {
      closeSocket();
      return { ok: true };
    }
    if (method === 'isOpen') return { open: !!(state.socket && state.socket.readyState === 1) };
    throw bridgeError('method_not_found', 'websocket.' + method);
  }

  function networkStatus() {
    if (!navigator.onLine) return 'offline';
    var c = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
    if (c && c.type) {
      if (c.type === 'wifi') return 'wifi';
      if (c.type === 'cellular') return 'cellular';
      if (c.type === 'ethernet') return 'ethernet';
    }
    return 'wifi';
  }

  var netHandler = null;
  function handleNetworkWatch(method, p) {
    if (method === 'start') {
      if (!netHandler) {
        netHandler = function () {
          emitApp('network.change', { status: networkStatus(), expensive: false });
        };
        window.addEventListener('online', netHandler);
        window.addEventListener('offline', netHandler);
      }
      return { ok: true };
    }
    if (method === 'stop') {
      stopNetworkWatchInternal();
      return { ok: true };
    }
    throw bridgeError('method_not_found', 'networkWatch.' + method);
  }

  /* ---------------- 相机/相册/麦克风 ---------------- */

  function fileInput(opts) {
    return new Promise(function (resolve, reject) {
      var input = document.createElement('input');
      input.type = 'file';
      input.accept = opts.accept || 'image/*';
      if (opts.capture) input.setAttribute('capture', opts.capture);
      if (opts.multiple) input.multiple = true;
      input.style.position = 'fixed';
      input.style.left = '-9999px';
      document.body.appendChild(input);
      input.onchange = function () {
        var files = Array.prototype.slice.call(input.files || []);
        input.remove();
        if (!files.length) reject({ code: 'user_cancel', message: '用户取消选择' });
        else resolve(files);
      };
      input.oncancel = function () { input.remove(); reject({ code: 'user_cancel', message: '用户取消选择' }); };
      input.click();
    });
  }

  async function imageFileToInfo(file) {
    var dataUrl = await blobToDataURL(file);
    return imageDataUrlInfo(dataUrl, file.type, file.size);
  }

  function imageDataUrlInfo(dataUrl, mime, size) {
    return new Promise(function (resolve) {
      var img = new Image();
      img.onload = function () {
        resolve({
          path: dataUrl,
          dataUrl: dataUrl,
          size: size || (dataUrl.length * 0.75),
          width: img.naturalWidth,
          height: img.naturalHeight,
          type: mime || 'image/jpeg'
        });
      };
      img.onerror = function () {
        resolve({ path: dataUrl, dataUrl: dataUrl, size: size || 0, width: 0, height: 0, type: mime || 'image/jpeg' });
      };
      img.src = dataUrl;
    });
  }

  function openCamera() {
    return new Promise(function (resolve, reject) {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        reject({ code: 'unsupported', message: '浏览器不支持 getUserMedia' });
        return;
      }
      var overlay = document.createElement('div');
      overlay.className = 'cam-overlay';
      overlay.innerHTML =
        '<div class="cam-card">' +
          '<video playsinline autoplay muted></video>' +
          '<div class="cam-top"><span>Web Camera</span><button class="cam-x" data-cam="cancel">×</button></div>' +
          '<div class="cam-bottom">' +
            '<button class="cam-flip" data-cam="flip" title="切换镜头">↺</button>' +
            '<button class="cam-shutter" data-cam="shot" title="拍照"></button>' +
            '<div class="cam-spacer"></div>' +
          '</div>' +
          '<p class="cam-hint">由浏览器原生相机提供 · 照片只在本地处理</p>' +
        '</div>';
      document.body.appendChild(overlay);
      var video = overlay.querySelector('video');
      var stream = null;
      var facing = 'environment';
      var settled = false;

      function cleanup() {
        if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
        overlay.remove();
      }
      function fail(err) {
        if (settled) return;
        settled = true;
        cleanup();
        reject(err);
      }
      async function start() {
        try {
          if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
          stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: facing }, audio: false });
          video.srcObject = stream;
          try { await video.play(); } catch (e) {}
        } catch (err) {
          var code = err && err.name === 'NotAllowedError' ? 'user_denied' : 'provider_error';
          fail({ code: code, message: err && err.name === 'NotAllowedError' ? '用户拒绝了相机权限' : ('相机不可用：' + (err.message || err)) });
        }
      }
      overlay.addEventListener('click', function (e) {
        var b = e.target.closest ? e.target.closest('[data-cam]') : null;
        if (!b) return;
        var action = b.getAttribute('data-cam');
        if (action === 'cancel') fail({ code: 'user_cancel', message: '用户取消拍照' });
        if (action === 'flip') { facing = facing === 'environment' ? 'user' : 'environment'; start(); }
        if (action === 'shot') {
          if (settled) return;
          var w = video.videoWidth || 800;
          var h = video.videoHeight || 600;
          var canvas = document.createElement('canvas');
          canvas.width = w; canvas.height = h;
          canvas.getContext('2d').drawImage(video, 0, 0, w, h);
          var dataUrl = canvas.toDataURL('image/jpeg', 0.86);
          settled = true;
          cleanup();
          var approx = Math.round(dataUrl.length * 0.75);
          resolve({ path: dataUrl, dataUrl: dataUrl, width: w, height: h, size: approx, type: 'image/jpeg' });
        }
      });
      start();
    });
  }

  async function chooseImages(p) {
    var count = Math.max(1, Number(p.count) || 1);
    var sourceType = Array.isArray(p.sourceType) ? p.sourceType : ['album', 'camera'];
    var wantCamera = sourceType.indexOf('camera') >= 0;
    var wantAlbum = sourceType.indexOf('album') >= 0;
    var items = [];
    if (wantCamera && count === 1) {
      if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
        if (wantAlbum) {
          var choose = await uiActionSheet(['拍照', '从相册选择'], p.title || '选择图片来源');
          if (choose < 0) throw { code: 'user_cancel', message: '用户取消' };
          if (choose === 0) items = [await openCamera()];
          else {
            var albumFiles = await fileInput({ accept: 'image/*' });
            items = await Promise.all(albumFiles.map(imageFileToInfo));
          }
        } else {
          items = [await openCamera()];
        }
      } else {
        var captureFiles = await fileInput({ accept: 'image/*', capture: 'environment' });
        items = await Promise.all(captureFiles.map(imageFileToInfo));
      }
    } else {
      var files = await fileInput({ accept: 'image/*', multiple: count > 1 });
      items = await Promise.all(files.slice(0, count).map(imageFileToInfo));
    }
    return items;
  }

  async function handleCamera(method, p) {
    if (method !== 'chooseImage') throw bridgeError('method_not_found', 'camera.' + method);
    var items = await chooseImages(p);
    return {
      tempFilePaths: items.map(function (x) { return x.path; }),
      tempFiles: items,
      base64: items[0] ? items[0].dataUrl : '',
      width: items[0] ? items[0].width : 0,
      height: items[0] ? items[0].height : 0,
      size: items[0] ? items[0].size : 0
    };
  }

  async function handlePhoto(method, p) {
    if (method !== 'chooseMedia') throw bridgeError('method_not_found', 'photo.' + method);
    var count = Math.max(1, Number(p.count) || 1);
    var files = await fileInput({ accept: p.mediaType === 'video' ? 'video/*' : 'image/*,video/*', multiple: count > 1 });
    var list = [];
    for (var i = 0; i < files.length && i < count; i++) {
      var f = files[i];
      if (f.type.indexOf('video') === 0) {
        var vUrl = URL.createObjectURL(f);
        state.blobUrls.push(vUrl);
        list.push({ tempFilePath: vUrl, size: f.size, fileType: 'video', duration: 0 });
      } else {
        var info = await imageFileToInfo(f);
        list.push({ tempFilePath: info.path, size: info.size, fileType: 'image', width: info.width, height: info.height });
      }
    }
    return { tempFiles: list, tempFilePaths: list.map(function (x) { return x.tempFilePath; }), type: p.mediaType || 'image' };
  }

  async function handleMicrophone(id, method, p) {
    if (method === 'start') {
      if (!navigator.mediaDevices || !window.MediaRecorder) throw bridgeError('unsupported', '浏览器不支持录音');
      if (state.recorders[id] && state.recorders[id].rec.state !== 'inactive') throw bridgeError('already_recording', '正在录音');
      var stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      var mime = MediaRecorder.isTypeSupported('audio/webm;codecs=opus') ? 'audio/webm;codecs=opus' :
        (MediaRecorder.isTypeSupported('audio/mp4') ? 'audio/mp4' : '');
      var rec = mime ? new MediaRecorder(stream, { mimeType: mime }) : new MediaRecorder(stream);
      var chunks = [];
      rec.ondataavailable = function (e) { if (e.data && e.data.size) chunks.push(e.data); };
      var item = { rec: rec, stream: stream, chunks: chunks, startedAt: Date.now() };
      state.recorders[id] = item;
      rec.start();
      return { ok: true };
    }
    if (method === 'stop') {
      var it = state.recorders[id];
      if (!it) throw bridgeError('not_recording', '当前没有录音');
      return await new Promise(function (resolve, reject) {
        it.rec.onstop = async function () {
          try {
            it.stream.getTracks().forEach(function (t) { t.stop(); });
            delete state.recorders[id];
            var blob = new Blob(it.chunks, { type: it.rec.mimeType || 'audio/webm' });
            resolve({
              tempFilePath: await blobToDataURL(blob),
              size: blob.size,
              duration: Math.round((Date.now() - it.startedAt) / 1000),
              mimeType: blob.type
            });
          } catch (e) { reject(bridgeError('provider_error', String(e))); }
        };
        try { it.rec.stop(); } catch (e) { reject(bridgeError('provider_error', String(e))); }
      });
    }
    throw bridgeError('method_not_found', 'microphone.' + method);
  }

  async function handleVideoRecord(method, p) {
    if (method !== 'record') throw bridgeError('method_not_found', 'videoRecord.' + method);
    var files = await fileInput({ accept: 'video/*', capture: 'environment' });
    var f = files[0];
    var vUrl = URL.createObjectURL(f);
    state.blobUrls.push(vUrl);
    return { tempFilePath: vUrl, size: f.size, duration: 0 };
  }

  async function handleImage(method, p) {
    if (method !== 'compress') throw bridgeError('method_not_found', 'image.' + method);
    var src = p.path || p.src;
    if (!src) throw bridgeError('invalid_params', 'path 必填');
    var quality = Math.max(0.1, Math.min(1, Number(p.quality) || 0.7));
    var maxWidth = Math.max(1, Number(p.maxWidth) || 1920);
    var img = await loadImage(src);
    var scale = Math.min(1, maxWidth / Math.max(img.naturalWidth, img.naturalHeight));
    var canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(img.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(img.naturalHeight * scale));
    var ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    var dataUrl = canvas.toDataURL('image/jpeg', quality);
    return {
      path: dataUrl, tempFilePath: dataUrl, size: Math.round(dataUrl.length * 0.75),
      originalSize: img.src.length, width: canvas.width, height: canvas.height
    };
  }

  function loadImage(src) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.onload = function () { resolve(img); };
      img.onerror = function () { reject(bridgeError('invalid_params', '图片无法读取')); };
      img.src = src;
    });
  }

  async function handleSavePhoto(method, p) {
    if (method !== 'save') throw bridgeError('method_not_found', 'savePhoto.' + method);
    var src = p.base64 ? (p.base64.indexOf('data:') === 0 ? p.base64 : 'data:image/jpeg;base64,' + p.base64) : p.path;
    if (!src) throw bridgeError('invalid_params', 'path 或 base64 必填');
    var blob = await urlToBlob(src);
    downloadBlob(blob, p.fileName || ('kinter-photo-' + Date.now() + '.jpg'));
    return { ok: true, saved: true, mode: 'download' };
  }

  /* ---------------- 音频/音乐/TTS ---------------- */

  function audioFor(id) {
    if (!state.audio[id]) {
      var a = new Audio();
      a.preload = 'auto';
      state.audio[id] = a;
    }
    return state.audio[id];
  }

  async function handleAudio(id, method, p) {
    var a = audioFor(id);
    if (method === 'play') {
      var src = p.path || p.src;
      if (!src) throw bridgeError('invalid_params', 'path 必填');
      a.src = src;
      a.loop = !!p.loop;
      a.volume = Math.max(0, Math.min(1, Number(p.volume) || 1));
      try { await a.play(); } catch (e) { throw bridgeError('provider_error', '音频播放失败：' + (e.message || e)); }
      return { ok: true };
    }
    if (method === 'pause') { a.pause(); return { ok: true }; }
    if (method === 'stop') { a.pause(); a.currentTime = 0; return { ok: true }; }
    if (method === 'seek') { a.currentTime = Math.max(0, Number(p.position) || 0); return { ok: true }; }
    throw bridgeError('method_not_found', 'audio.' + method);
  }

  function musicFor(id) {
    if (!state.music[id]) state.music[id] = new Audio();
    return state.music[id];
  }

  async function handleMusic(id, method, p) {
    var a = musicFor(id);
    if (method === 'play' || method === 'playTest') {
      var src = p.path || p.src;
      if (method === 'playTest' || !src) src = BASE_URL + 'testmusic.mp3';
      if (!src) throw bridgeError('invalid_params', 'path 必填');
      a.src = src;
      a.loop = !!p.loop;
      a.volume = Math.max(0, Math.min(1, p.volume == null ? 1 : Number(p.volume)));
      try { await a.play(); } catch (e) { throw bridgeError('provider_error', '音乐播放失败：' + (e.message || e)); }
      return { ok: true, path: src };
    }
    if (method === 'pause') { a.pause(); return { ok: true }; }
    if (method === 'resume') { try { await a.play(); } catch (e) { throw bridgeError('provider_error', String(e)); } return { ok: true }; }
    if (method === 'stop') { a.pause(); a.currentTime = 0; state.music[id] = null; return { ok: true }; }
    if (method === 'seek') { a.currentTime = Math.max(0, Number(p.position) || 0); return { ok: true }; }
    if (method === 'setVolume') { a.volume = Math.max(0, Math.min(1, Number(p.volume) || 0)); return { ok: true, volume: a.volume }; }
    if (method === 'getState') {
      return { playing: !a.paused, position: a.currentTime, duration: a.duration || 0, volume: a.volume, loop: a.loop };
    }
    throw bridgeError('method_not_found', 'music.' + method);
  }

  function handleTTS(method, p) {
    if (!window.speechSynthesis) throw bridgeError('unsupported', '浏览器不支持语音合成');
    if (method === 'speak') {
      var text = String(p.text || '');
      if (!text) throw bridgeError('invalid_params', 'text 必填');
      return new Promise(function (resolve) {
        var u = new SpeechSynthesisUtterance(text);
        u.lang = p.lang || 'zh-CN';
        u.rate = Math.max(0.1, Math.min(2, Number(p.rate) || 1));
        u.pitch = Number(p.pitch) || 1;
        u.volume = Math.max(0, Math.min(1, p.volume == null ? 1 : Number(p.volume)));
        u.onend = function () { resolve({ ok: true }); };
        u.onerror = function () { resolve({ ok: true, cancelled: true }); };
        speechSynthesis.speak(u);
      });
    }
    if (method === 'stop') { speechSynthesis.cancel(); return { ok: true }; }
    if (method === 'isSpeaking') return { speaking: speechSynthesis.speaking };
    throw bridgeError('method_not_found', 'tts.' + method);
  }

  /* ---------------- 扫码/定位/设备 ---------------- */

  async function handleQRScan(method, p) {
    if (method !== 'scan') throw bridgeError('method_not_found', 'qrScan.' + method);
    if (!('BarcodeDetector' in window)) throw bridgeError('unsupported', '当前浏览器不支持原生条码识别');
    var detector = new BarcodeDetector({ formats: ['qr_code'] });
    var stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
    var overlay = document.createElement('div');
    overlay.className = 'cam-overlay';
    overlay.innerHTML = '<div class="cam-card"><video playsinline autoplay muted></video><div class="cam-top"><span>扫描二维码</span><button class="cam-x" data-qr="cancel">×</button></div><div class="cam-bottom"><div class="cam-hint">将二维码放入取景框</div></div></div>';
    document.body.appendChild(overlay);
    var video = overlay.querySelector('video');
    video.srcObject = stream;
    try { await video.play(); } catch (e) {}
    return await new Promise(function (resolve, reject) {
      var settled = false;
      function cleanup() {
        stream.getTracks().forEach(function (t) { t.stop(); });
        overlay.remove();
      }
      function done(v) {
        if (settled) return;
        settled = true; cleanup();
        if (v) resolve(v); else reject({ code: 'user_cancel', message: '用户取消' });
      }
      overlay.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('[data-qr="cancel"]')) done(null);
      });
      var timer = setInterval(async function () {
        if (settled) { clearInterval(timer); return; }
        if (video.readyState < 2) return;
        try {
          var codes = await detector.detect(video);
          if (codes && codes.length) done({ text: codes[0].rawValue, format: 'qr_code' });
        } catch (e) {}
      }, 350);
    });
  }

  function locationPayload(pos) {
    return {
      latitude: pos.coords.latitude,
      longitude: pos.coords.longitude,
      accuracy: pos.coords.accuracy,
      altitude: pos.coords.altitude,
      heading: pos.coords.heading,
      speed: pos.coords.speed,
      timestamp: pos.timestamp
    };
  }

  function handleLocation(method, p) {
    if (method !== 'getCurrent') throw bridgeError('method_not_found', 'location.' + method);
    if (!navigator.geolocation) throw bridgeError('unsupported', '浏览器不支持定位');
    return new Promise(function (resolve, reject) {
      navigator.geolocation.getCurrentPosition(function (pos) { resolve(locationPayload(pos)); }, function (err) {
        var code = err.code === 1 ? 'user_denied' : 'provider_error';
        reject({ code: code, message: err.message || '定位失败' });
      }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
    });
  }

  function stopWatchers() {
    if (state.watch.id != null && navigator.geolocation) {
      navigator.geolocation.clearWatch(state.watch.id);
    }
    state.watch = {};
  }

  function handleLocationWatch(id, method, p) {
    if (method === 'start') {
      if (!navigator.geolocation) throw bridgeError('unsupported', '浏览器不支持定位');
      stopWatchers();
      state.watch.points = [];
      state.watch.id = navigator.geolocation.watchPosition(function (pos) {
        var point = locationPayload(pos);
        state.watch.points.push(point);
        if (state.watch.points.length > 100) state.watch.points.shift();
        emitApp('location.change', point);
      }, function () {}, { enableHighAccuracy: true });
      return { ok: true, watching: true };
    }
    if (method === 'stop') {
      var count = state.watch.points ? state.watch.points.length : 0;
      stopWatchers();
      return { ok: true, points: count };
    }
    if (method === 'isWatching') return { watching: state.watch.id != null };
    throw bridgeError('method_not_found', 'locationWatch.' + method);
  }

  function handleDeviceInfo(method, p) {
    if (method !== 'get') throw bridgeError('method_not_found', 'deviceInfo.' + method);
    return {
      model: 'Browser',
      systemName: navigator.platform || 'Web',
      systemVersion: navigator.userAgent,
      name: 'Kinter for Web',
      vendorId: '',
      screenWidth: window.screen.width,
      screenHeight: window.screen.height,
      scale: window.devicePixelRatio || 1,
      language: navigator.language,
      platform: 'web',
      brand: 'Kinter',
      browser: navigator.userAgent
    };
  }

  async function handleBattery(method, p) {
    if (method !== 'get') throw bridgeError('method_not_found', 'battery.' + method);
    if (navigator.getBattery) {
      try {
        var b = await navigator.getBattery();
        var st = b.charging ? 'charging' : (b.level >= 1 ? 'full' : 'unplugged');
        return { level: b.level, state: st };
      } catch (e) {}
    }
    return { level: 0, state: 'unknown' };
  }

  function handleNetwork(method, p) {
    if (method !== 'get') throw bridgeError('method_not_found', 'network.' + method);
    return { status: networkStatus(), expensive: false };
  }

  function handleMotion(method, p) {
    if (method !== 'deviceMotion') throw bridgeError('method_not_found', 'motion.' + method);
    return new Promise(function (resolve, reject) {
      if (!window.DeviceMotionEvent) { reject({ code: 'unsupported', message: '浏览器不支持运动传感器' }); return; }
      var done = false;
      function handler(e) {
        if (done) return;
        done = true;
        window.removeEventListener('devicemotion', handler);
        var a = e.accelerationIncludingGravity || e.acceleration || {};
        resolve({ x: a.x || 0, y: a.y || 0, z: a.z || 0, interval: e.interval || 0 });
      }
      window.addEventListener('devicemotion', handler);
      setTimeout(function () { if (!done) { done = true; window.removeEventListener('devicemotion', handler); reject({ code: 'provider_error', message: '没有收到传感器数据' }); } }, 5000);
    });
  }

  /* ---------------- 系统能力 ---------------- */

  async function handleClipboard(method, p) {
    if (method === 'set') {
      if (!navigator.clipboard) throw bridgeError('unsupported', '浏览器不支持剪贴板写入');
      await navigator.clipboard.writeText(String(p.data == null ? '' : p.data));
      return { ok: true };
    }
    if (method === 'get') {
      if (!navigator.clipboard) throw bridgeError('unsupported', '浏览器不支持剪贴板读取');
      try { return { data: await navigator.clipboard.readText() }; }
      catch (e) { throw bridgeError('user_denied', '读取剪贴板需要页面获得焦点和用户授权'); }
    }
    throw bridgeError('method_not_found', 'clipboard.' + method);
  }

  async function handleClipboardImage(method, p) {
    if (!navigator.clipboard) throw bridgeError('unsupported', '浏览器不支持剪贴板');
    if (method === 'get') {
      try {
        var items = await navigator.clipboard.read();
        for (var i = 0; i < items.length; i++) {
          var types = items[i].types;
          for (var j = 0; j < types.length; j++) {
            if (types[j].indexOf('image/') === 0) {
              var blob = await items[i].getType(types[j]);
              return { data: await blobToDataURL(blob), type: types[j] };
            }
          }
        }
        throw { code: 'not_found', message: '剪贴板没有图片' };
      } catch (e) {
        if (e && e.code) throw e;
        throw bridgeError('user_denied', '读取剪贴板图片需要用户授权');
      }
    }
    if (method === 'set') {
      if (!window.ClipboardItem) throw bridgeError('unsupported', '浏览器不支持写入图片');
      var src = p.path || p.data || p.base64;
      if (!src) throw bridgeError('invalid_params', 'path 或 data 必填');
      var b = await urlToBlob(src.indexOf('data:') === 0 ? src : 'data:image/png;base64,' + src);
      await navigator.clipboard.write([new ClipboardItem({ [b.type || 'image/png']: b })]);
      return { ok: true };
    }
    throw bridgeError('method_not_found', 'clipboardImage.' + method);
  }

  function handleVibrate(method, p) {
    if (method !== 'short' && method !== 'long') throw bridgeError('method_not_found', 'vibrate.' + method);
    if (navigator.vibrate) navigator.vibrate(method === 'long' ? 400 : 30);
    return { ok: true, supported: !!navigator.vibrate };
  }

  var wakeLock = null;
  async function handleScreenAwake(method, p) {
    if (method === 'enable') {
      if (!('wakeLock' in navigator)) throw bridgeError('unsupported', '浏览器不支持屏幕常亮');
      try {
        wakeLock = await navigator.wakeLock.request('screen');
        wakeLock.addEventListener('release', function () { wakeLock = null; });
        return { ok: true };
      } catch (e) { throw bridgeError('provider_error', '屏幕常亮申请失败'); }
    }
    if (method === 'disable') {
      if (wakeLock) { await wakeLock.release(); wakeLock = null; }
      return { ok: true };
    }
    throw bridgeError('method_not_found', 'screenAwake.' + method);
  }

  async function handleNotification(method, p) {
    if (!('Notification' in window)) throw bridgeError('unsupported', '浏览器不支持通知');
    if (method === 'requestPermission') {
      var perm = Notification.permission === 'default' ? await Notification.requestPermission() : Notification.permission;
      return { granted: perm === 'granted', status: perm };
    }
    if (method === 'schedule') {
      if (Notification.permission !== 'granted') throw bridgeError('user_denied', '通知权限未开启');
      var after = Math.max(0, Number(p.after) || 1) * 1000;
      setTimeout(function () {
        try {
          new Notification(p.title || 'Kinter', { body: p.body || '', icon: BASE_URL + 'icon.png' });
        } catch (e) {}
      }, after);
      return { ok: true, after: after };
    }
    throw bridgeError('method_not_found', 'notification.' + method);
  }

  function permissionId(p) {
    var name = String((p && p.permission) || '');
    var map = {
      'scope.camera': 'camera', 'scope.record': 'microphone', 'scope.userLocation': 'geolocation',
      'scope.notification': 'notifications', 'camera': 'camera', 'microphone': 'microphone',
      'record': 'microphone', 'location': 'geolocation', 'notification': 'notifications',
      'clipboard': 'clipboard-read'
    };
    return map[name] || name;
  }

  async function handlePermission(method, p) {
    var id = permissionId(p);
    if (method === 'getStatus') {
      var st = id === 'camera' || id === 'microphone' || id === 'geolocation' || id === 'notifications'
        ? await queryPerm({ query: id === 'notifications' ? 'notifications' : id })
        : 'prompt';
      return { permission: id, status: st === 'granted' ? 'authorized' : (st === 'denied' ? 'denied' : 'notDetermined') };
    }
    if (method === 'getSetting') {
      var obj = {};
      for (var i = 0; i < PERMISSIONS.length; i++) {
        var q = PERMISSIONS[i];
        var s = await queryPerm(q);
        obj[q.id] = s === 'granted' ? 'authorized' : (s === 'denied' ? 'denied' : 'notDetermined');
      }
      return obj;
    }
    if (method === 'request') {
      await requestPermission(id);
      var after = await queryPerm({ query: id === 'notifications' ? 'notifications' : id });
      return { permission: id, status: after === 'granted' ? 'authorized' : (after === 'denied' ? 'denied' : 'notDetermined') };
    }
    if (method === 'openSettings') {
      throw bridgeError('unsupported', '浏览器权限请在地址栏或系统设置中修改');
    }
    throw bridgeError('method_not_found', 'permission.' + method);
  }

  async function handleShare(method, p) {
    if (method !== 'text') throw bridgeError('method_not_found', 'share.' + method);
    if (navigator.share) {
      try {
        await navigator.share({ title: p.title || '', text: p.text || p.content || '', url: p.url || undefined });
        return { ok: true, shared: true };
      } catch (e) {
        if (e && e.name === 'AbortError') throw bridgeError('user_cancel', '用户取消分享');
        throw bridgeError('provider_error', '分享失败');
      }
    }
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(String(p.text || p.content || p.url || ''));
      return { ok: true, shared: false, copied: true };
    }
    throw bridgeError('unsupported', '浏览器不支持分享');
  }

  function handleOpenURL(method, p) {
    var url = String(p.url || '');
    if (!url) throw bridgeError('invalid_params', 'url 必填');
    if (/^(file|javascript):/i.test(url)) throw bridgeError('invalid_params', '不允许打开该协议');
    if (/^https?:/i.test(url) && isBlockedUrl(url)) throw bridgeError('blocked', '该地址被运行时禁止访问');
    if (method === 'canOpen') return { canOpen: /^(https?:|tel:|sms:|mailto:)/i.test(url) };
    if (method === 'open') {
      if (/^(https?:|tel:|sms:|mailto:)/i.test(url)) window.open(url, '_blank', 'noopener');
      else throw bridgeError('unsupported', '浏览器无法打开该 URL Scheme');
      return { ok: true };
    }
    throw bridgeError('method_not_found', 'openURL.' + method);
  }

  function handleCommunication(method, p) {
    var target = String(p.phone || p.number || p.to || p.address || '');
    if (method === 'call') {
      if (!target) throw bridgeError('invalid_params', 'phone 必填');
      location.href = 'tel:' + target;
      return { ok: true, mode: 'browser' };
    }
    if (method === 'sms') {
      if (!target) throw bridgeError('invalid_params', 'phone 必填');
      location.href = 'sms:' + target + (p.content ? '?body=' + encodeURIComponent(p.content) : '');
      return { ok: true, mode: 'browser' };
    }
    if (method === 'mail') {
      if (!target) throw bridgeError('invalid_params', 'address 必填');
      location.href = 'mailto:' + target + '?subject=' + encodeURIComponent(p.subject || '') + '&body=' + encodeURIComponent(p.content || p.body || '');
      return { ok: true, mode: 'browser' };
    }
    throw bridgeError('method_not_found', 'communication.' + method);
  }

  /* ---------------- 事件绑定 ---------------- */

  function bindEvents() {
    document.querySelectorAll('.nav-item').forEach(function (b) {
      b.addEventListener('click', function () { showView(b.getAttribute('data-nav')); });
    });
    if (el.importTop) el.importTop.addEventListener('click', pickZip);
    if (el.heroImport) el.heroImport.addEventListener('click', pickZip);
    if (el.emptyImport) el.emptyImport.addEventListener('click', pickZip);
    if (el.heroSettings) el.heroSettings.addEventListener('click', function () { showView('settings'); });
    if (el.pickZip) el.pickZip.addEventListener('click', function (e) { e.stopPropagation(); if (el.zipInput) el.zipInput.click(); });
    if (el.zipInput) el.zipInput.addEventListener('change', function () {
      if (el.zipInput.files && el.zipInput.files[0]) importZip(el.zipInput.files[0]);
      el.zipInput.value = '';
    });
    if (el.dropzone) {
      el.dropzone.addEventListener('click', function (e) {
        if (e.target.closest && (e.target.closest('button') || e.target.closest('input'))) return;
        if (el.zipInput) el.zipInput.click();
      });
      ['dragenter', 'dragover'].forEach(function (ev) {
        el.dropzone.addEventListener(ev, function (e) { e.preventDefault(); el.dropzone.classList.add('drag'); });
      });
      ['dragleave', 'drop'].forEach(function (ev) {
        el.dropzone.addEventListener(ev, function (e) { e.preventDefault(); el.dropzone.classList.remove('drag'); });
      });
      el.dropzone.addEventListener('drop', function (e) {
        if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0]) importZip(e.dataTransfer.files[0]);
      });
    }
    if (el.searchInput) el.searchInput.addEventListener('input', function () {
      state.query = el.searchInput.value || '';
      renderApps();
    });
    if (el.sortTabs) el.sortTabs.addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('[data-sort]') : null;
      if (!b) return;
      state.sort = b.getAttribute('data-sort');
      el.sortTabs.querySelectorAll('button').forEach(function (x) { x.classList.toggle('active', x === b); });
      renderApps();
    });
    if (el.diskTree) el.diskTree.addEventListener('click', function (e) {
      var row = e.target.closest ? e.target.closest('[data-disk-path]') : null;
      if (!row) return;
      diskNavigate(row.getAttribute('data-disk-path'));
    });
    if (el.diskBreadcrumb) el.diskBreadcrumb.addEventListener('click', function (e) {
      var crumb = e.target.closest ? e.target.closest('[data-disk-path]') : null;
      if (!crumb) return;
      diskNavigate(crumb.getAttribute('data-disk-path'));
    });
    if (el.diskList) el.diskList.addEventListener('click', function (e) {
      var row = e.target.closest ? e.target.closest('[data-disk-index]') : null;
      if (!row) return;
      var entry = state.diskEntries[Number(row.getAttribute('data-disk-index'))];
      openDiskEntry(entry);
    });
    if (el.diskList) el.diskList.addEventListener('keydown', function (e) {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      var row = e.target.closest ? e.target.closest('[data-disk-index]') : null;
      if (!row) return;
      e.preventDefault();
      var entry = state.diskEntries[Number(row.getAttribute('data-disk-index'))];
      openDiskEntry(entry);
    });
    var diskSearchTimer = null;
    if (el.diskSearch) el.diskSearch.addEventListener('input', function () {
      state.diskQuery = el.diskSearch.value || '';
      if (diskSearchTimer) clearTimeout(diskSearchTimer);
      diskSearchTimer = setTimeout(renderDisk, 160);
    });
    if (el.diskRefresh) el.diskRefresh.addEventListener('click', function () {
      renderDisk();
      toast('磁盘已刷新', 1200);
    });
    if (el.diskTree) el.diskTree.addEventListener('keydown', function (e) {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      var row = e.target.closest ? e.target.closest('[data-disk-path]') : null;
      if (!row) return;
      e.preventDefault();
      diskNavigate(row.getAttribute('data-disk-path'));
    });
    if (el.appGrid) el.appGrid.addEventListener('click', function (e) {
      var menu = e.target.closest ? e.target.closest('[data-menu]') : null;
      if (menu) { openDataManager(menu.getAttribute('data-menu')); return; }
      var open = e.target.closest ? e.target.closest('[data-open]') : null;
      var card = e.target.closest ? e.target.closest('.app-card') : null;
      if (open) openApp(open.getAttribute('data-open'));
      else if (card) openApp(card.getAttribute('data-id'));
    });
    if (el.dataList) el.dataList.addEventListener('click', function (e) {
      var manage = e.target.closest ? e.target.closest('[data-manage]') : null;
      if (manage) { openDataManager(manage.getAttribute('data-manage')); return; }
      var del = e.target.closest ? e.target.closest('[data-delete]') : null;
      if (del) deleteApp(del.getAttribute('data-delete'));
    });
    if (el.permList) el.permList.addEventListener('click', function (e) {
      var row = e.target.closest ? e.target.closest('[data-perm]') : null;
      if (!row) return;
      requestPermission(row.getAttribute('data-perm'));
    });
    if (el.refreshPerms) el.refreshPerms.addEventListener('click', refreshPermissions);
    if (el.clearAll) el.clearAll.addEventListener('click', clearAll);
    if (el.exportLibrary) el.exportLibrary.addEventListener('click', exportLibrary);
    if (el.importBackup) el.importBackup.addEventListener('change', function () {
      if (el.importBackup.files && el.importBackup.files[0]) importBackup(el.importBackup.files[0]);
      el.importBackup.value = '';
    });
    if (el.themeToggle) el.themeToggle.addEventListener('click', toggleTheme);

    if (el.runnerBack) el.runnerBack.addEventListener('click', function () {
      if (!state.running) return;
      if (state.running.stack.length > 1) {
        state.running.stack.pop();
        var target = state.running.stack[state.running.stack.length - 1];
        loadPage(target, 'back');
      } else {
        closeRunner();
      }
    });
    if (el.runnerReload) el.runnerReload.addEventListener('click', function () {
      if (state.running) loadPage(state.running.page, 'replace');
    });
    if (el.runnerConsoleToggle) el.runnerConsoleToggle.addEventListener('click', function () { toggleConsole(); });
    if (el.clearConsole) el.clearConsole.addEventListener('click', function () {
      state.logs = [];
      state.unreadLogs = 0;
      renderConsole();
    });
    if (el.closeConsole) el.closeConsole.addEventListener('click', function () { toggleConsole(false); });
    if (el.runnerClose) el.runnerClose.addEventListener('click', closeRunner);
    if (el.appFrame) el.appFrame.addEventListener('load', function () {
      installFrameLogger();
      flushEvents();
    });

    // 运行器 iframe 未带 allow-same-origin，其源为不透明源（origin 序列化为 "null"），
    // postMessage 无法用固定 targetOrigin 精确指定目标源；因此边界改为：
    // 1) event.source 严格等于当前 iframe 的 contentWindow（严格比较，不用 instanceof Window）；
    // 2) 消息 type 白名单（kfw-bridge / kfw-toast / kfw-log）；
    // 3) bridgeCall 再校验 APP_ID 与当前运行应用一致。
    // 运行器已关闭/切换时 state.running 为空，消息直接丢弃。
    window.addEventListener('message', function (e) {
      var win = el.appFrame && el.appFrame.contentWindow;
      if (!win || e.source !== win || !state.running || !e.data) return;
      if (e.data.type === 'kfw-bridge') { handleIncomingBridge(e); return; }
      if (e.data.type === 'kfw-toast') toast(String(e.data.text || ''), 1800);
      if (e.data.type === 'kfw-log') addRuntimeLog(String(e.data.level || 'log'), String(e.data.message || ''));
    });
    document.addEventListener('keydown', function (e) {
      var meta = e.metaKey || e.ctrlKey;
      if (meta && String(e.key).toLowerCase() === 'k') {
        e.preventDefault();
        showView('apps');
        if (el.searchInput) el.searchInput.focus();
        return;
      }
      if (meta && String(e.key).toLowerCase() === 'i') {
        e.preventDefault();
        pickZip();
        return;
      }
      if (meta && (e.key === '1' || e.key === '2' || e.key === '3' || e.key === '4')) {
        e.preventDefault();
        showView(e.key === '1' ? 'apps' : (e.key === '2' ? 'disk' : (e.key === '3' ? 'import' : 'settings')));
        return;
      }
      if (meta && String(e.key).toLowerCase() === 'l' && state.running) {
        e.preventDefault();
        toggleConsole();
        return;
      }
      if (e.key === 'Escape') {
        if (state.modals.length) return;
        if (state.consoleOpen) { toggleConsole(false); return; }
        if (state.running) closeRunner();
      }
    });
    if (window.matchMedia) {
      try {
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
          if (state.settings.theme === 'system') applyTheme();
        });
      } catch (e) {}
    }
  }

  /* ---------------- 启动 ---------------- */

  function init() {
    el = {
      appGrid: $('appGrid'), emptyState: $('emptyState'), appCountText: $('appCountText'),
      navCount: $('navCount'), statApps: $('statApps'), statCaps: $('statCaps'), statSize: $('statSize'),
      storageBar: $('storageBar'), storageText: $('storageText'),
      viewDisk: $('viewDisk'), diskUsed: $('diskUsed'), diskFree: $('diskFree'),
      diskFiles: $('diskFiles'), diskBar: $('diskBar'), diskCount: $('diskCount'),
      diskTree: $('diskTree'), diskBreadcrumb: $('diskBreadcrumb'), diskSearch: $('diskSearch'),
      diskRefresh: $('diskRefresh'), diskList: $('diskList'), diskEmpty: $('diskEmpty'),
      diskStatus: $('diskStatus'),
      settingsStorage: $('settingsStorage'), settingsStorageBar: $('settingsStorageBar'),
      dataList: $('dataList'), permList: $('permList'), refreshPerms: $('refreshPerms'),
      importPreview: $('importPreview'), importLog: $('importLog'), zipInput: $('zipInput'),
      dropzone: $('dropzone'), searchInput: $('searchInput'), sortTabs: $('sortTabs'),
      pageTitle: $('pageTitle'), pageSub: $('pageSub'), importTop: $('importTop'),
      heroImport: $('heroImport'), heroSettings: $('heroSettings'), emptyImport: $('emptyImport'),
      pickZip: $('pickZip'), themeToggle: $('themeToggle'),
      clearAll: $('clearAll'), exportLibrary: $('exportLibrary'), importBackup: $('importBackup'),
      runner: $('runner'), runnerName: $('runnerName'), runnerIcon: $('runnerIcon'),
      runnerMeta: $('runnerMeta'), runnerBack: $('runnerBack'), runnerReload: $('runnerReload'),
      runnerClose: $('runnerClose'), appFrame: $('appFrame'),
      runnerConsole: $('runnerConsole'), runnerConsoleToggle: $('runnerConsoleToggle'),
      consoleOutput: $('consoleOutput'), consoleCount: $('consoleCount'),
      consoleBadge: $('consoleBadge'), clearConsole: $('clearConsole'), closeConsole: $('closeConsole'),
      modalRoot: $('modalRoot'), toastRoot: $('toastRoot')
    };
    state.apps = loadIndex();
    reconcileIndex();
    loadSettings();
    applyTheme();
    bindEvents();
    if (!lsAvailable()) {
      toast('当前浏览器环境禁止 LocalStorage，应用与数据将无法保存', 4000);
    }
    renderConsole();
    renderApps();
    renderSettings();
    showView('apps');

    window.KFW = window.KFW || {};
    window.KFW.bridgeCall = bridgeCall;
    window.KFW.toast = toast;
    window.KFW.modal = uiModal;
    window.KFW.actionSheet = uiActionSheet;
    window.KFW.openApp = openApp;
    window.KFW.version = '1.0.0';
    window.KFW.ui = { toast: toast, modal: uiModal, actionSheet: uiActionSheet };
    window.KFW.getStorageInfo = function () { return { used: storageUsed(), capacity: CAPACITY }; };
    window.KFW.emit = emitApp;
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
