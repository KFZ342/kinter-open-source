/* Kinter Web 控制台 Service Worker：只缓存外壳，不碰接口和小程序页面 */
var CACHE = 'kinter-shell-v5';
var SHELL = ['/', '/console.css?v=4', '/console.js?v=4',
             '/pwa-192.png', '/pwa-512.png', '/manifest.webmanifest'];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      return Promise.all(SHELL.map(function (url) {
        return fetch(url, { cache: 'reload' }).then(function (r) {
          if (r && r.ok) return cache.put(url, r);
        }).catch(function () {});
      }));
    }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k !== CACHE; })
        .map(function (k) { return caches.delete(k); }));
    }).then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function (event) {
  var req = event.request;
  if (req.method !== 'GET') return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // 接口、运行器、小程序资源、SDK 永远走网络，避免缓存造成“假装在线”
  if (url.pathname.indexOf('/api/') === 0 ||
      url.pathname.indexOf('/apps/') === 0 ||
      url.pathname.indexOf('/sdk/') === 0 ||
      url.pathname === '/run' ||
      url.pathname === '/sw.js' ||
      url.pathname.indexOf('/web-bridge') === 0 ||
      url.pathname === '/healthz') return;

  if (url.pathname === '/' || url.pathname === '/index.html') {
    event.respondWith(
      fetch(req).catch(function () {
        return caches.match('/');
      })
    );
    return;
  }
  // 控制台样式/脚本：网络优先，离线才用缓存，避免升级后一直跑旧代码
  if (url.pathname === '/console.css' || url.pathname === '/console.js') {
    event.respondWith(
      fetch(req).then(function (resp) {
        var copy = resp.clone();
        caches.open(CACHE).then(function (c) { c.put(req, copy); });
        return resp;
      }).catch(function () {
        return caches.match(req);
      })
    );
    return;
  }
  if (SHELL.indexOf(url.pathname + (url.search || '')) >= 0 ||
      SHELL.indexOf(url.pathname) >= 0) {
    event.respondWith(
      caches.match(req).then(function (hit) {
        return hit || fetch(req);
      })
    );
  }
});
