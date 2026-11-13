/*
 * Kinter Web Bridge
 * 在浏览器里复刻原生 WKWebView 的桥接协议：
 *   - 提供 window.webkit.messageHandlers.bridge.postMessage
 *   - 把调用转发到设备上的 /api/bridge
 *   - 回包走 window.__wxBridgeCallback，与 SDK/wx.js 完全兼容
 *   - router / popup 这类原生 UI 行为改由页面自身实现
 */
(function () {
  'use strict';

  var APP_ID = window.__KINTER_WEB_APP_ID__ || '';
  var seq = 0;

  // ---------- 通用 ----------
  function bridgeCallback(payload) {
    try {
      if (window.__wxBridgeCallback) window.__wxBridgeCallback(payload);
    } catch (e) { /* 页面自己的错误不该影响桥接 */ }
  }

  function reply(callbackId, ok, data, error) {
    bridgeCallback({ callbackId: callbackId, ok: !!ok, data: data, error: error });
  }

  function parentRunner() {
    try {
      if (window.parent && window.parent !== window && window.parent.KinterRunner) {
        return window.parent.KinterRunner;
      }
    } catch (e) { /* 跨域时忽略 */ }
    return null;
  }

  function notifyParent(message) {
    try {
      if (window.parent && window.parent !== window) {
        window.parent.postMessage(Object.assign({ kinter: true }, message), '*');
      }
    } catch (e) { /* ignore */ }
  }

  function appURL(path) {
    if (/^(https?|about|data):/.test(path)) return path;
    return '/apps/' + encodeURIComponent(APP_ID) + '/' + String(path || '').replace(/^\/+/, '');
  }

  // ---------- 网络 ----------
  function callServer(callbackId, module, method, params) {
    var body = { appId: APP_ID, module: module, method: method, params: params || {}, callbackId: callbackId };
    fetch('/api/bridge', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).then(function (resp) {
      return resp.text().then(function (text) {
        var parsed;
        try { parsed = JSON.parse(text); } catch (e) {
          reply(callbackId, false, null, { code: 'bad_response', message: '设备返回了非 JSON 响应' });
          return;
        }
        if (!resp.ok || parsed.ok === false) {
          reply(callbackId, false, null, parsed.error || { code: 'http_' + resp.status, message: '调用失败' });
          return;
        }
        // 网关的返回值统一包在 data.result 里
        var data = parsed.data;
        if (data && typeof data === 'object' && Object.prototype.hasOwnProperty.call(data, 'result')) {
          data = data.result;
        }
        reply(callbackId, true, data);
      });
    }).catch(function (e) {
      reply(callbackId, false, null, { code: 'network_error', message: '无法连接设备服务：' + e.message });
    });
  }

  // ---------- router ----------
  function handleRouter(callbackId, method, params) {
    var url = params.url || '';
    var runner = parentRunner();

    switch (method) {
      case 'navigateTo':
      case 'redirectTo':
      case 'reLaunch':
        if (runner) {
          runner.navigate(method === 'navigateTo' ? 'push'
                          : method === 'redirectTo' ? 'replace' : 'relaunch', url);
        } else {
          location.href = appURL(url);
        }
        reply(callbackId, true, { ok: true });
        break;

      case 'navigateBack':
        if (runner) {
          runner.back(params.delta || 1);
        } else if (history.length > 1) {
          history.back();
        }
        reply(callbackId, true, { ok: true });
        break;

      case 'getStack':
        reply(callbackId, true, { stack: runner ? runner.getStack() : [url] });
        break;

      default:
        reply(callbackId, false, null, { code: 'method_not_found', message: 'router.' + method });
    }
  }

  // ---------- popup（页面内自绘，观感对齐 iOS） ----------
  function injectStyle() {
    if (document.getElementById('kinter-popup-style')) return;
    var css = document.createElement('style');
    css.id = 'kinter-popup-style';
    css.textContent = [
      '.kw-mask{position:fixed;inset:0;background:rgba(0,0,0,.35);z-index:2147483000;',
      'display:flex;align-items:center;justify-content:center;font:15px/1.4 -apple-system,"PingFang SC",sans-serif}',
      '.kw-box{width:270px;background:#fff;border-radius:14px;overflow:hidden;text-align:center;color:#1c1c1e}',
      '@media (prefers-color-scheme:dark){.kw-box{background:#2c2c2e;color:#f2f2f7}.kw-btn{border-color:rgba(84,84,88,.5)!important}}',
      '.kw-title{font-weight:600;font-size:16px;padding:18px 16px 6px}',
      '.kw-content{font-size:13.5px;color:#8e8e93;padding:0 16px 16px;max-height:50vh;overflow:auto;white-space:pre-wrap}',
      '.kw-actions{display:flex;border-top:.5px solid rgba(60,60,67,.2)}',
      '.kw-btn{flex:1;padding:12px 6px;border:0;background:transparent;font-size:16px;color:#007aff;cursor:pointer}',
      '.kw-btn.cancel{font-weight:600}',
      '.kw-btn.destructive{color:#ff3b30}',
      '.kw-toast{position:fixed;left:50%;bottom:20%;transform:translateX(-50%);background:rgba(30,30,32,.92);',
      'color:#fff;padding:11px 16px;border-radius:11px;font:13.5px/1.4 -apple-system,"PingFang SC",sans-serif;',
      'z-index:2147483001;max-width:70vw;text-align:center}',
      '.kw-sheet{position:fixed;left:0;right:0;bottom:0;z-index:2147483000;padding:8px 10px calc(10px + env(safe-area-inset-bottom,0px));',
      'font:16px/1.4 -apple-system,"PingFang SC",sans-serif}',
      '.kw-sheet-inner{background:#fff;border-radius:14px;overflow:hidden;margin-bottom:8px}',
      '@media (prefers-color-scheme:dark){.kw-sheet-inner{background:#2c2c2e}.kw-sheet-item{color:#f2f2f7!important;border-color:rgba(84,84,88,.5)!important}}',
      '.kw-sheet-title{font-size:13px;color:#8e8e93;padding:14px 16px 8px;text-align:center}',
      '.kw-sheet-item{display:block;width:100%;border:0;background:transparent;color:#007aff;padding:14px;font-size:17px;',
      'border-top:.5px solid rgba(60,60,67,.2);cursor:pointer}',
      '.kw-sheet-cancel{width:100%;border:0;border-radius:14px;background:#fff;color:#007aff;font-size:17px;font-weight:600;',
      'padding:14px;cursor:pointer}'
    ].join('');
    document.head.appendChild(css);
  }

  var overlays = [];

  function removeOverlay(el) {
    if (!el || !el.parentNode) return;
    el.parentNode.removeChild(el);
    overlays = overlays.filter(function (x) { return x !== el; });
  }

  function handlePopup(callbackId, method, params) {
    injectStyle();
    switch (method) {
      case 'toast': {
        var toast = document.createElement('div');
        toast.className = 'kw-toast';
        toast.textContent = params.text || '';
        document.body.appendChild(toast);
        overlays.push(toast);
        setTimeout(function () { removeOverlay(toast); }, (params.duration || 1.8) * 1000);
        reply(callbackId, true, { ok: true });
        break;
      }

      case 'modal': {
        var mask = document.createElement('div');
        mask.className = 'kw-mask';

        var box = document.createElement('div');
        box.className = 'kw-box';

        var title = document.createElement('div');
        title.className = 'kw-title';
        title.textContent = params.title || '';

        var content = document.createElement('div');
        content.className = 'kw-content';
        content.textContent = params.content || '';

        var actions = document.createElement('div');
        actions.className = 'kw-actions';

        function mkBtn(text, cls, handler) {
          var b = document.createElement('button');
          b.className = 'kw-btn ' + (cls || '');
          b.textContent = text;
          b.addEventListener('click', handler);
          return b;
        }

        if (params.cancelText) {
          actions.appendChild(mkBtn(params.cancelText, 'cancel', function () {
            removeOverlay(mask);
            reply(callbackId, true, { confirmed: false });
          }));
        }
        actions.appendChild(mkBtn(params.confirmText || '确定', params.cancelText ? 'cancel' : 'cancel', function () {
          removeOverlay(mask);
          reply(callbackId, true, { confirmed: true });
        }));

        box.appendChild(title);
        if (params.content) box.appendChild(content);
        box.appendChild(actions);
        mask.appendChild(box);
        document.body.appendChild(mask);
        overlays.push(mask);
        break;
      }

      case 'actionSheet': {
        var sheetMask = document.createElement('div');
        sheetMask.className = 'kw-mask';
        sheetMask.style.alignItems = 'flex-end';

        var sheet = document.createElement('div');
        sheet.className = 'kw-sheet';

        var inner = document.createElement('div');
        inner.className = 'kw-sheet-inner';
        if (params.title) {
          var st = document.createElement('div');
          st.className = 'kw-sheet-title';
          st.textContent = params.title;
          inner.appendChild(st);
        }
        (params.items || []).forEach(function (label, index) {
          var item = document.createElement('button');
          item.className = 'kw-sheet-item';
          item.textContent = label;
          item.addEventListener('click', function () {
            removeOverlay(sheetMask);
            reply(callbackId, true, { index: index, cancelled: false });
          });
          inner.appendChild(item);
        });
        sheet.appendChild(inner);

        var cancel = document.createElement('button');
        cancel.className = 'kw-sheet-cancel';
        cancel.textContent = params.cancelText || '取消';
        cancel.addEventListener('click', function () {
          removeOverlay(sheetMask);
          reply(callbackId, true, { cancelled: true });
        });
        sheet.appendChild(cancel);

        sheetMask.appendChild(sheet);
        document.body.appendChild(sheetMask);
        overlays.push(sheetMask);
        break;
      }

      case 'dismissAll':
        overlays.slice().forEach(removeOverlay);
        reply(callbackId, true, { ok: true });
        break;

      case 'getStatus':
        reply(callbackId, true, { visible: overlays.length > 0 });
        break;

      default:
        reply(callbackId, false, null, { code: 'method_not_found', message: 'popup.' + method });
    }
  }

  // ---------- 应用间跳转 ----------
  function handleAppOpen(callbackId, params) {
    var target = params.appId || '';
    if (!target) {
      reply(callbackId, false, null, { code: 'invalid_params', message: 'appId 必填' });
      return;
    }
    callServerLocal(callbackId, 'app', 'open', params, function (ok, data, error) {
      if (!ok) { reply(callbackId, false, null, error); return; }
      var runner = parentRunner();
      if (runner) {
        runner.openApp(target, data && data.name);
      } else {
        location.href = '/run?appId=' + encodeURIComponent(target) + '&page=index';
      }
      reply(callbackId, true, { ok: true });
    });
  }

  function callServerLocal(callbackId, module, method, params, done) {
    fetch('/api/bridge', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ appId: APP_ID, module: module, method: method, params: params || {}, callbackId: callbackId })
    }).then(function (r) {
      return r.json();
    }).then(function (parsed) {
      done(parsed.ok !== false, parsed.data, parsed.error);
    }).catch(function (e) {
      done(false, null, { code: 'network_error', message: e.message });
    });
  }

  // ---------- Web 原生相机 / 麦克风 ----------
  // 安全边界不变：先让设备的 /api/bridge 做 manifest / 安全模式 / 权限策略判定，
  // 通过后才使用浏览器自己的摄像头和麦克风，采集结果只在浏览器内处理。

  function postBridge(payload) {
    return fetch('/api/bridge', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    }).then(function (r) { return r.json(); });
  }

  var webSeq = 0;
  function authorizeWebNative(module, method, params) {
    return postBridge({
      appId: APP_ID, module: module, method: method, callbackId: 'web_native_' + (++webSeq),
      params: Object.assign({}, params || {}, { __kinterWebNative: true })
    }).then(function (body) {
      if (body && body.ok !== false) return true;
      var err = (body && body.error) || { code: 'permission_denied', message: 'Web 原生采集未获授权' };
      var e = new Error(err.message || err.code);
      e.code = err.code;
      throw e;
    });
  }

  function stopStream(stream) {
    if (!stream) return;
    try { stream.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
  }

  function fitCanvas(source, maxSide) {
    var w = source.videoWidth || source.naturalWidth || source.width;
    var h = source.videoHeight || source.naturalHeight || source.height;
    var scale = Math.min(1, (maxSide || 1280) / Math.max(w, h));
    var canvas = document.createElement('canvas');
    canvas.width = Math.round(w * scale);
    canvas.height = Math.round(h * scale);
    canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  function imagePayload(canvas) {
    var dataUrl = canvas.toDataURL('image/jpeg', 0.85);
    var comma = dataUrl.indexOf(',');
    var b64 = dataUrl.slice(comma + 1);
    var bytes = Math.round(b64.length * 0.75);
    return { dataUrl: dataUrl, size: bytes, width: canvas.width, height: canvas.height };
  }

  // 相册 / 没有摄像头的桌面：用 input[type=file]，手机上会直接调起系统相机
  function pickFromInput(count, useCamera, done) {
    var input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    if (count > 1) input.multiple = true;
    if (useCamera) input.setAttribute('capture', 'environment');
    input.style.cssText = 'position:fixed;left:-1000px;top:-1000px';
    document.body.appendChild(input);
    var settled = false;
    function finish(files) {
      if (settled) return;
      settled = true;
      input.remove();
      if (!files || !files.length) { done({ cancel: true }); return; }
      var out = [], left = files.length;
      Array.prototype.slice.call(files).slice(0, count).forEach(function (file) {
        var reader = new FileReader();
        reader.onload = function () {
          var img = new Image();
          img.onload = function () {
            var item = imagePayload(fitCanvas(img, 1280));
            out.push(item);
            if (--left === 0) done({ items: out });
          };
          img.onerror = function () { if (--left === 0) done({ items: out }); };
          img.src = String(reader.result);
        };
        reader.onerror = function () { if (--left === 0) done({ items: out }); };
        reader.readAsDataURL(file);
      });
    }
    input.addEventListener('change', function () { finish(input.files); });
    input.click();
    // 大多数浏览器取消文件选择不会触发 change；借窗口重新聚焦兜底
    setTimeout(function () {
      window.addEventListener('focus', function onFocus() {
        window.removeEventListener('focus', onFocus);
        setTimeout(function () { if (!settled) finish(null); }, 800);
      }, { once: true });
    }, 300);
  }

  function injectCameraStyle() {
    if (document.getElementById('kinter-webcam-style')) return;
    var css = document.createElement('style');
    css.id = 'kinter-webcam-style';
    css.textContent = [
      '.kwcam-mask{position:fixed;inset:0;z-index:2147483100;background:rgba(0,0,0,.72);',
      'display:flex;align-items:center;justify-content:center;padding:18px;',
      '-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);}',
      '.kwcam-panel{width:100%;max-width:520px;max-height:92vh;border-radius:20px;overflow:hidden;',
      'background:#000;display:flex;flex-direction:column;box-shadow:0 24px 60px rgba(0,0,0,.45);}',
      '.kwcam-top{display:flex;align-items:center;justify-content:space-between;padding:12px 16px;color:#fff;}',
      '.kwcam-top span{font:600 14px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;}',
      '.kwcam-top button{border:0;background:rgba(255,255,255,.16);color:#fff;border-radius:16px;',
      'padding:6px 13px;font:500 13px -apple-system,BlinkMacSystemFont,sans-serif;}',
      '.kwcam-stage{position:relative;background:#111;flex:1;min-height:220px;display:flex;align-items:center;justify-content:center;}',
      '.kwcam-stage video{width:100%;height:100%;max-height:62vh;object-fit:cover;display:block;}',
      '.kwcam-stage .kwcam-no{color:#8e8e93;font:400 13px -apple-system,sans-serif;padding:40px;}',
      '.kwcam-bottom{display:flex;align-items:center;justify-content:space-between;padding:14px 22px 20px;}',
      '.kwcam-flip{border:0;background:rgba(255,255,255,.14);color:#fff;border-radius:18px;padding:8px 12px;',
      'font:500 12px -apple-system,sans-serif;}',
      '.kwcam-shutter{width:66px;height:66px;border-radius:50%;border:3px solid rgba(255,255,255,.55);',
      'background:transparent;padding:5px;}',
      '.kwcam-shutter i{display:block;width:100%;height:100%;border-radius:50%;background:#fff;}',
      '.kwcam-done{border:0;background:#fff;color:#111;border-radius:18px;padding:8px 12px;',
      'font:600 12px -apple-system,sans-serif;}',
      '.kwcam-count{position:absolute;left:50%;bottom:98px;transform:translateX(-50%);',
      'color:#fff;background:rgba(0,0,0,.5);border-radius:12px;padding:3px 9px;',
      'font:500 12px -apple-system,sans-serif;}'
    ].join('');
    document.head.appendChild(css);
  }

  function captureWebCamera(count, done) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      done({ unavailable: true });
      return;
    }
    injectCameraStyle();
    count = Math.max(1, Math.min(count || 1, 9));

    var mask = document.createElement('div');
    mask.className = 'kwcam-mask';
    mask.innerHTML = '<div class="kwcam-panel">'
      + '<div class="kwcam-top"><span>Web 相机</span><button class="kwcam-cancel">取消</button></div>'
      + '<div class="kwcam-stage"><video autoplay playsinline muted></video>'
      + '<div class="kwcam-count" hidden></div></div>'
      + '<div class="kwcam-bottom"><button class="kwcam-flip">翻转</button>'
      + '<button class="kwcam-shutter" aria-label="拍照"><i></i></button>'
      + '<button class="kwcam-done" hidden>完成</button></div></div>';
    document.body.appendChild(mask);

    var video = mask.querySelector('video');
    var shutter = mask.querySelector('.kwcam-shutter');
    var flip = mask.querySelector('.kwcam-flip');
    var doneBtn = mask.querySelector('.kwcam-done');
    var countEl = mask.querySelector('.kwcam-count');
    var stream = null, facing = 'environment', items = [], finished = false;

    function close() {
      stopStream(stream);
      stream = null;
      mask.remove();
    }
    function finish(result) {
      if (finished) return;
      finished = true;
      close();
      done(result);
    }
    function updateCount() {
      if (items.length === 0) return;
      countEl.hidden = false;
      countEl.textContent = '已拍 ' + items.length + ' / ' + count;
      if (count > 1) {
        doneBtn.hidden = false;
        doneBtn.textContent = '完成 (' + items.length + ')';
      }
    }
    function openStream() {
      stopStream(stream);
      navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: facing }, width: { ideal: 1920 }, height: { ideal: 1440 } },
        audio: false
      }).then(function (s) {
        if (finished) { stopStream(s); return; }
        stream = s;
        video.srcObject = s;
        var p = video.play();
        if (p && p.catch) p.catch(function () {});
      }).catch(function (err) {
        var code = (err && err.name) || '';
        if (code === 'NotAllowedError' || code === 'SecurityError') {
          finish({ error: { code: 'userDenied', message: '浏览器未授权使用摄像头' } });
        } else if (code === 'NotFoundError' || code === 'OverconstrainedError' || code === 'NotReadableError') {
          finish({ unavailable: code });
        } else {
          finish({ error: { code: 'unsupported', message: '无法打开浏览器摄像头：' + (err.message || code) } });
        }
      });
    }

    mask.querySelector('.kwcam-cancel').addEventListener('click', function () {
      finish({ cancel: true });
    });
    flip.addEventListener('click', function () {
      facing = facing === 'environment' ? 'user' : 'environment';
      openStream();
    });
    shutter.addEventListener('click', function () {
      if (!video.videoWidth) return;
      items.push(imagePayload(fitCanvas(video, 1280)));
      if (items.length >= count && count === 1) {
        finish({ items: items });
      } else {
        updateCount();
        if (items.length >= count) shutter.disabled = true;
      }
    });
    doneBtn.addEventListener('click', function () { finish({ items: items }); });

    openStream();
  }

  function toCameraPayload(items) {
    return {
      tempFilePaths: items.map(function (x) { return x.dataUrl; }),
      base64: items[0].dataUrl,
      size: items[0].size,
      width: items[0].width,
      height: items[0].height
    };
  }

  function handleWebCamera(callbackId, params) {
    var source = params.sourceType || ['album', 'camera'];
    if (typeof source === 'string') source = [source];
    var allowCamera = source.indexOf('camera') >= 0;
    var count = parseInt(params.count, 10) || 1;

    authorizeWebNative('camera', 'chooseImage', params).then(function () {
      if (!allowCamera) {
        pickFromInput(count, false, function (r) { finishCamera(callbackId, r); });
        return;
      }
      captureWebCamera(count, function (r) {
        if (r.unavailable && source.indexOf('album') < 0) {
          // 浏览器没有可用摄像头：退回设备相机（真机上仍然可用）
          callServer(callbackId, 'camera', 'chooseImage', params);
          return;
        }
        if (r.unavailable) { pickFromInput(count, true, function (r2) { finishCamera(callbackId, r2); }); return; }
        // 浏览器拒绝了摄像头权限，但调用方允许相册：退一步让用户选图
        if (r.error && r.error.code === 'userDenied' && source.indexOf('album') >= 0) {
          pickFromInput(count, false, function (r2) { finishCamera(callbackId, r2); });
          return;
        }
        finishCamera(callbackId, r);
      });
    }).catch(function (e) {
      reply(callbackId, false, null, { code: e.code || 'permission_denied', message: e.message });
    });
  }

  function finishCamera(callbackId, r) {
    if (!r || r.cancel) {
      reply(callbackId, false, null, { code: 'userDenied', message: '用户取消拍照' });
      return;
    }
    if (r.error) {
      reply(callbackId, false, null, r.error);
      return;
    }
    reply(callbackId, true, toCameraPayload(r.items || []));
  }

  // ---------- 麦克风 ----------
  var webRecorder = null;

  function handleWebMicrophone(callbackId, method, params) {
    if (method === 'start') {
      authorizeWebNative('microphone', 'start', params).then(function () {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.MediaRecorder) {
          callServer(callbackId, 'microphone', 'start', params);
          return;
        }
        navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
          var mime = '';
          ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'].some(function (m) {
            if (MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(m)) { mime = m; return true; }
            return false;
          });
          var rec = mime ? new MediaRecorder(stream, { mimeType: mime }) : new MediaRecorder(stream);
          var chunks = [], startedAt = Date.now();
          rec.ondataavailable = function (e) { if (e.data && e.data.size) chunks.push(e.data); };
          rec.onstop = function () {
            stopStream(stream);
            var type = rec.mimeType || mime || 'audio/webm';
            var blob = new Blob(chunks, { type: type });
            var reader = new FileReader();
            reader.onload = function () {
              var dataUrl = String(reader.result);
              webRecorder = null;
              reply(callbackId, true, {
                tempFilePath: dataUrl,
                base64: dataUrl,
                size: blob.size,
                duration: Math.round((Date.now() - startedAt) / 1000)
              });
            };
            reader.readAsDataURL(blob);
          };
          webRecorder = { rec: rec, stream: stream };
          rec.start();
          reply(callbackId, true, { ok: true, recording: true });
        }).catch(function (err) {
          var code = (err && err.name) === 'NotAllowedError' ? 'userDenied' : 'unsupported';
          reply(callbackId, false, null, { code: code, message: '浏览器无法录音：' + ((err && err.message) || '') });
        });
      }).catch(function (e) {
        reply(callbackId, false, null, { code: e.code || 'permission_denied', message: e.message });
      });
      return;
    }
    if (method === 'stop') {
      if (!webRecorder) {
        callServer(callbackId, 'microphone', 'stop', params);
        return;
      }
      var rec = webRecorder.rec;
      webRecorder = null;
      try { rec.stop(); } catch (e) {
        reply(callbackId, false, null, { code: 'provider_error', message: '停止录音失败' });
      }
      return;
    }
    reply(callbackId, false, null, { code: 'method_not_found', message: 'microphone.' + method });
  }

  // ---------- 入口 ----------
  function route(payload) {
    var callbackId = payload.callbackId || ('web_' + (++seq));
    var module = payload.module || '';
    var method = payload.method || '';
    var params = payload.params || {};

    if (!APP_ID) {
      reply(callbackId, false, null, { code: 'bridge_unavailable', message: '页面缺少 Kinter 会话标识' });
      return;
    }

    if (module === 'router') return handleRouter(callbackId, method, params);
    if (module === 'popup') return handlePopup(callbackId, method, params);
    if (module === 'app' && method === 'open') return handleAppOpen(callbackId, params);
    if (module === 'camera' && method === 'chooseImage') return handleWebCamera(callbackId, params);
    if (module === 'microphone') return handleWebMicrophone(callbackId, method, params);

    callServer(callbackId, module, method, params);
  }

  window.webkit = window.webkit || {};
  window.webkit.messageHandlers = window.webkit.messageHandlers || {};
  window.webkit.messageHandlers.bridge = {
    postMessage: function (payload) { route(payload || {}); }
  };

  // 设备事件（websocket / 共享值 / 网络变化）走长轮询，再喂给 wx.on
  var since = 0;
  var polling = false;
  function poll() {
    if (polling) return;
    polling = true;
    fetch('/api/poll?since=' + since + '&wait=20&appId=' + encodeURIComponent(APP_ID))
      .then(function (r) { return r.json(); })
      .then(function (body) {
        if (body.seq) since = body.seq;
        (body.events || []).forEach(function (ev) { onEvent(ev); });
      })
      .catch(function () { /* 非 200 / 断网，稍后重试 */ })
      .then(function () {
        polling = false;
        setTimeout(poll, 500);
      });
  }

  function onEvent(ev) {
    if (!ev || !ev.event) return;
    // 与原生 evaluateJavaScript("window.__wxEmitBatch([...])") 等价
    try {
      if (window.__wxEmitBatch) window.__wxEmitBatch([{ event: ev.event, data: ev.data }]);
    } catch (e) { /* ignore */ }
  }

  document.addEventListener('DOMContentLoaded', function () { poll(); });
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(poll, 0);
  }
})();
