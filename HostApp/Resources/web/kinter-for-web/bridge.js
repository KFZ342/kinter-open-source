/* Kinter for Web 的 iframe 桥：通过 postMessage RPC 与父页能力网关通信。
   子窗口不直接访问父页对象；父页按 event.source 校验来源，并校验 APP_ID。 */
(function () {
  'use strict';

  var APP_ID = window.__KFW_APP_ID__ || '';
  var pending = {};
  var seq = 0;
  var BRIDGE_TIMEOUT_MS = 30000;

  function reply(callbackId, ok, data, error) {
    try {
      if (window.__wxBridgeCallback) {
        window.__wxBridgeCallback({ callbackId: callbackId, ok: !!ok, data: data, error: error });
      }
    } catch (e) { /* 页面自身异常不应影响桥接 */ }
  }

  function callParent(module, method, params, noTimeout) {
    return new Promise(function (resolve, reject) {
      seq += 1;
      var callbackId = 'kfw_' + Date.now() + '_' + Math.random().toString(36).slice(2) + '_' + seq;
      var settled = false;
      var timer = null;
      // 模态类调用（showModal / showActionSheet）等待用户操作，不设超时
      if (!noTimeout) {
        timer = setTimeout(function () {
          if (settled) return;
          settled = true;
          delete pending[callbackId];
          reject({ code: 'timeout', message: '宿主调用超时：' + module + '.' + method });
        }, BRIDGE_TIMEOUT_MS);
      }
      pending[callbackId] = { resolve: resolve, reject: reject, timer: timer };
      try {
        // 父页同源，但子帧被沙箱化为不透明源；targetOrigin 无法写具体 URL，故用 '*'。
        // 父页在监听处严格校验 event.source === 当前运行帧的 contentWindow，并校验 APP_ID。
        window.parent.postMessage({
          type: 'kfw-bridge',
          callbackId: callbackId,
          appId: APP_ID,
          module: module,
          method: method,
          params: params || {}
        }, '*');
      } catch (e) {
        if (timer) clearTimeout(timer);
        delete pending[callbackId];
        reject({ code: 'post_message_failed', message: String(e) });
      }
    });
  }

  window.addEventListener('message', function (e) {
    // 严格绑定父窗口（严格比较，不用 instanceof Window）；非父窗口的消息一律丢弃
    if (e.source !== window.parent) return;
    var p = e.data;
    if (!p || p.type !== 'kfw-bridge-reply' || !p.callbackId) return;
    var entry = pending[p.callbackId];
    if (!entry) return;
    if (entry.timer) clearTimeout(entry.timer);
    delete pending[p.callbackId];
    if (p.ok) entry.resolve(p.data == null ? {} : p.data);
    else entry.reject(p.error || { code: 'unknown' });
  });

  window.webkit = window.webkit || {};
  window.webkit.messageHandlers = window.webkit.messageHandlers || {};
  window.webkit.messageHandlers.bridge = {
    postMessage: function (payload) {
      payload = payload || {};
      var module = payload.module || '';
      var method = payload.method || '';
      var params = payload.params || {};
      var noTimeout = !!payload.noTimeout;
      callParent(module, method, params, noTimeout).then(function (data) {
        reply(payload.callbackId, true, data == null ? {} : data);
      }).catch(function (err) {
        reply(payload.callbackId, false, null, err && err.code ? err : {
          code: 'provider_error', message: String((err && err.message) || err)
        });
      });
    }
  };
})();
