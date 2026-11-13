/* Kinter Web 控制台：应用库 / 导入 / 商店 / 设置，全部走设备上的本地服务 */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };
  var store = {
    get token() { return localStorage.getItem('kinter.token') || ''; },
    set token(v) { if (v) localStorage.setItem('kinter.token', v); else localStorage.removeItem('kinter.token'); },
    get tab() { return localStorage.getItem('kinter.tab') || 'import'; },
    set tab(v) { localStorage.setItem('kinter.tab', v); }
  };

  var loggedOut = false;

  var state = {
    meta: null,
    apps: [],
    settings: null,
    pendingFile: null,
    preview: null,
    currentTab: 'import'
  };

  // URL 里带的令牌（App 二维码就是这么生成的），自动落盘
  var qs = new URLSearchParams(location.search);
  if (qs.get('token')) store.token = qs.get('token');

  // ---------------- 基础 ----------------
  function toast(text, ms) {
    var el = $('toast');
    el.textContent = text;
    el.classList.add('show');
    clearTimeout(toast._t);
    toast._t = setTimeout(function () { el.classList.remove('show'); }, ms || 2000);
  }

  function headers(extra) {
    var h = Object.assign({ 'Content-Type': 'application/json' }, extra || {});
    if (store.token) h['X-Kinter-Token'] = store.token;
    return h;
  }

  function api(path, options) {
    return fetch(path, Object.assign({ headers: headers() }, options || {}))
      .then(function (resp) {
        return resp.text().then(function (text) {
          var body;
          try { body = JSON.parse(text); } catch (e) { body = { ok: false, raw: text }; }
          if (!resp.ok || body.ok === false) {
            var err = new Error((body.error && body.error.message) || ('HTTP ' + resp.status));
            err.code = body.error && body.error.code;
            err.status = resp.status;
            throw err;
          }
          return body;
        });
      });
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function fmtSize(bytes) {
    if (!bytes && bytes !== 0) return '';
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(2) + ' MB';
  }

  function fmtTime(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  // ---------------- 导航 ----------------
  var titles = { import: '导入应用', library: '应用库', store: '商店', settings: '设置' };

  function switchTab(tab, opts) {
    opts = opts || {};
    state.currentTab = tab;
    store.tab = tab;
    Array.prototype.forEach.call(document.querySelectorAll('.screen'), function (el) {
      el.hidden = el.dataset.screen !== tab;
    });
    Array.prototype.forEach.call(document.querySelectorAll('.tab'), function (el) {
      el.classList.toggle('active', el.dataset.tab === tab);
    });
    $('navTitle').textContent = titles[tab] || '';
    $('navBack').hidden = true;
    $('content').scrollTop = 0;
    window.scrollTo(0, 0);

    if (tab === 'library') loadApps();
    if (tab === 'store') loadStore();
    if (tab === 'settings') loadSettings();
    if (tab === 'import' && !opts.keepPreview) hidePreview();
  }

  Array.prototype.forEach.call(document.querySelectorAll('.tab'), function (el) {
    el.addEventListener('click', function () { switchTab(el.dataset.tab); });
  });

  $('navInfo').addEventListener('click', function () { showInfoSheet(); });

  // ---------------- 元信息 ----------------
  function loadMeta() {
    return api('/api/meta').then(function (meta) {
      state.meta = meta;
      renderInfo(meta);
      if (!document.getElementById('webToken').textContent.includes('•')) {
        // 第一次拿到数据时补上
      }
      return meta;
    }).catch(function (e) {
      if (e.status === 401) {
        toast('令牌无效：请到「设置 → Web 访问」复制令牌并填写');
      }
      throw e;
    });
  }

  function renderInfo(meta) {
    var rows = [
      ['版本', 'v' + meta.version + '（#' + meta.build + '）'],
      ['设备', meta.device],
      ['系统', meta.system],
      ['局域网 IP', meta.localIP || '未获取到'],
      ['服务地址', meta.baseURL || '—'],
      ['已装应用', String(meta.installedApps)],
      ['可用能力', String(meta.capabilityCount) + ' 项'],
      ['安全模式', meta.securityMode ? '已开启' : '已关闭']
    ];
    $('infoGrid').innerHTML = rows.map(function (r) {
      return '<div class="k">' + esc(r[0]) + '</div><div class="v">' + esc(r[1]) + '</div>';
    }).join('');

    if ($('aboutVersion')) $('aboutVersion').textContent = 'Kinter v' + meta.version + '（#' + meta.build + '）';
    $('accountRow').textContent = meta.account && meta.account.loggedIn
      ? (meta.account.name || meta.account.username)
      : '未登录';
    $('accountRow').classList.toggle('dim', !(meta.account && meta.account.loggedIn));
  }

  // ---------------- 导入 ----------------
  $('pickZip').addEventListener('click', function () { $('zipInput').click(); });
  $('dropHintBtn').addEventListener('click', function () { $('zipInput').click(); });
  $('zipInput').addEventListener('change', function (e) {
    var file = e.target.files && e.target.files[0];
    if (file) previewFile(file);
    e.target.value = '';
  });

  // 拖拽
  window.addEventListener('dragover', function (e) { e.preventDefault(); });
  window.addEventListener('drop', function (e) {
    e.preventDefault();
    var file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
    if (file) {
      switchTab('import', { keepPreview: true });
      previewFile(file);
    }
  });

  function setImportStatus(title, body, busy, actions) {
    $('importStatus').hidden = false;
    $('importStatusTitle').textContent = title;
    $('importStatusBody').textContent = body || '';
    $('importSpinner').classList.toggle('on', !!busy);
    var box = $('importStatusActions');
    box.innerHTML = '';
    (actions || []).forEach(function (a) {
      var b = document.createElement('button');
      b.className = 'btn small' + (a.primary ? ' primary' : '');
      b.textContent = a.title;
      b.addEventListener('click', a.action);
      box.appendChild(b);
    });
  }

  function hidePreview() {
    $('previewCard').hidden = true;
  }

  function clearPending() {
    state.pendingFile = null;
    state.preview = null;
  }

  function previewFile(file) {
    if (!/\.zip$/i.test(file.name)) { toast('请选择 .zip 安装包'); return; }
    state.pendingFile = file;
    setImportStatus('正在检查安装包…', file.name + ' · ' + fmtSize(file.size), true);
    $('previewCard').hidden = true;

    fetch('/api/apps/preview', { method: 'POST', headers: headers(), body: file })
      .then(function (r) { return r.text().then(function (t) { var b = JSON.parse(t); if (!r.ok || b.ok === false) throw new Error((b.error && b.error.message) || '检查失败'); return b; }); })
      .then(function (preview) {
        state.preview = preview;
        $('importStatus').hidden = true;
        $('previewCard').hidden = false;
        $('previewName').textContent = preview.name;
        $('previewMeta').textContent = 'v' + preview.version + ' · ' + preview.appId + (preview.installed ? ' · 已安装（将覆盖）' : '');
        $('previewIcon').textContent = (preview.name || 'A').slice(0, 1);
        $('previewCategory').value = '未分类';

        var caps = []
          .concat((preview.sensitive || []).map(function (c) { return { c: c, cls: 'danger', label: '敏感' }; }))
          .concat((preview.standard || []).map(function (c) { return { c: c, cls: 'warn', label: '标准' }; }))
          .concat((preview.normal || []).map(function (c) { return { c: c, cls: '', label: '普通' }; }))
          .concat((preview.unknown || []).map(function (c) { return { c: c, cls: 'danger', label: '未知' }; }));
        $('previewCaps').innerHTML = caps.length
          ? caps.map(function (x) { return '<span class="cap ' + x.cls + '">' + esc(x.c) + ' · ' + x.label + '</span>'; }).join('')
          : '<span class="cap">该应用未声明任何能力</span>';
      })
      .catch(function (e) {
        setImportStatus('无法安装', e.message, false);
      });
  }

  $('cancelInstall').addEventListener('click', function () {
    hidePreview();
    clearPending();
    $('importStatus').hidden = true;
  });

  $('confirmInstall').addEventListener('click', function () {
    if (!state.pendingFile) { toast('先选择一个安装包'); return; }
    var category = $('previewCategory').value.trim() || '未分类';
    var file = state.pendingFile;
    var url = '/api/apps/import?overwrite=1&category=' + encodeURIComponent(category) +
              '&filename=' + encodeURIComponent(file.name);
    setImportStatus('正在安装…', file.name, true);
    $('previewCard').hidden = true;

    fetch(url, { method: 'POST', headers: headers(), body: file })
      .then(function (r) { return r.text().then(function (t) { var b = JSON.parse(t); if (!r.ok || b.ok === false) throw new Error((b.error && b.error.message) || '安装失败'); return b; }); })
      .then(function (res) {
        var warns = (res.warnings || []).length ? '\n提示：' + res.warnings.join('；') : '';
        setImportStatus('安装成功', res.name + ' v' + res.version + warns, false, [
          { title: '打开应用', primary: true, action: function () { openApp(res.appId, res.name); } },
          { title: '去应用库', action: function () { switchTab('library'); } }
        ]);
        hidePreview();
        clearPending();
        loadApps();
        loadMeta().catch(function () {});
      })
      .catch(function (e) {
        setImportStatus('安装失败', e.message, false, [
          { title: '重新选择', action: function () { $('zipInput').click(); } }
        ]);
      });
  });

  // ---------------- 应用库 ----------------
  function openApp(appId, name, entry) {
    var url = '/run?appId=' + encodeURIComponent(appId) +
              '&name=' + encodeURIComponent(name || '') +
              '&page=' + encodeURIComponent(entry || 'index');
    location.href = url;
  }

  function loadApps() {
    return api('/api/apps').then(function (body) {
      state.apps = body.apps || [];
      renderLibrary();
    }).catch(function (e) {
      if (e.status === 401) $('libraryList').innerHTML = '<div class="empty"><div class="empty-title">需要访问令牌</div><div class="empty-sub">请到「设置 → Web 访问」复制令牌</div></div>';
    });
  }

  function renderLibrary() {
    var keyword = ($('search').value || '').trim().toLowerCase();
    var apps = state.apps.filter(function (a) {
      return !keyword || a.name.toLowerCase().indexOf(keyword) >= 0 || a.appId.toLowerCase().indexOf(keyword) >= 0;
    });

    $('libraryEmpty').hidden = apps.length > 0;
    if (!apps.length) {
      $('libraryList').innerHTML = '';
      return;
    }

    var byCat = {};
    apps.forEach(function (a) {
      var cat = a.category || '未分类';
      (byCat[cat] = byCat[cat] || []).push(a);
    });
    var cats = Object.keys(byCat).sort();

    $('libraryList').innerHTML = cats.map(function (cat) {
      var rows = byCat[cat].slice().sort(function (x, y) { return x.name < y.name ? -1 : 1; }).map(function (a) {
        var caps = (a.capabilities || []).length;
        return '' +
          '<div class="app-row">' +
            '<div class="app-icon">' + (a.iconURL ? '<img src="' + esc(a.iconURL) + '" alt="">' : esc(a.name.slice(0, 1))) + '</div>' +
            '<div class="row-main">' +
              '<div class="row-title">' + esc(a.name) + '</div>' +
              '<div class="row-meta">v' + esc(a.version) + ' · ' + caps + ' 项能力' + (a.price > 0 ? ' · ¥' + a.price : '') + '</div>' +
            '</div>' +
            '<div class="app-actions">' +
              '<button class="app-btn solid" data-run="' + esc(a.appId) + '">打开</button>' +
              '<button class="app-btn more" data-manage="' + esc(a.appId) + '">⋯</button>' +
            '</div>' +
          '</div>';
      }).join('');
      return '<div class="card"><div class="section-head">' + esc(cat) + '</div>' + rows + '</div>';
    }).join('');

    $('libraryList').querySelectorAll('[data-run]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var app = state.apps.find(function (x) { return x.appId === btn.dataset.run; });
        if (app) openApp(app.appId, app.name, app.entry);
      });
    });
    $('libraryList').querySelectorAll('[data-manage]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var app = state.apps.find(function (x) { return x.appId === btn.dataset.manage; });
        if (app) showManageSheet(app);
      });
    });
  }

  $('search').addEventListener('input', renderLibrary);

  // ---------------- 管理弹层 ----------------
  function openSheet(title, html) {
    $('sheetTitle').textContent = title;
    $('sheetBody').innerHTML = html;
    $('mask').hidden = false;
    $('sheet').hidden = false;
  }

  function closeSheet() {
    $('mask').hidden = true;
    $('sheet').hidden = true;
  }

  $('sheetClose').addEventListener('click', closeSheet);
  $('mask').addEventListener('click', closeSheet);

  function showManageSheet(app) {
    var caps = app.capabilities || [];
    var capsHtml = caps.length ? caps.map(function (c) {
      return '<div class="cap-toggle">' +
        '<div class="cap-name">' + esc(c.name || c.module) +
          '<small>' + esc(c.module) + ' · ' + esc(c.level) + '</small></div>' +
        '<label class="switch"><input type="checkbox" data-cap="' + esc(c.module) + '"' + (c.enabled ? ' checked' : '') + '><i></i></label>' +
      '</div>';
    }).join('') : '<div class="row-line sub">该应用未声明任何能力。</div>';

    openSheet(app.name, '' +
      '<div class="field"><label for="mCategory">分类</label><input id="mCategory" value="' + esc(app.category || '未分类') + '"></div>' +
      '<div class="section-head" style="padding-top:14px">权限（' + caps.length + ' 项）</div>' +
      '<div style="max-height:250px;overflow:auto">' + capsHtml + '</div>' +
      '<div class="form-actions" style="margin-top:16px">' +
        '<button class="btn primary" id="mSave">保存</button>' +
        '<button class="btn danger" id="mDelete">卸载应用</button>' +
      '</div>');

    $('mSave').addEventListener('click', function () {
      var disabled = [];
      $('sheetBody').querySelectorAll('[data-cap]').forEach(function (input) {
        if (!input.checked) disabled.push(input.dataset.cap);
      });
      api('/api/apps/update', {
        method: 'POST',
        body: JSON.stringify({ appId: app.appId, category: $('mCategory').value.trim(), disabledCapabilities: disabled })
      }).then(function () {
        toast('已保存');
        closeSheet();
        loadApps();
      }).catch(function (e) { toast(e.message); });
    });

    $('mDelete').addEventListener('click', function () {
      if (!confirm('卸载「' + app.name + '」？应用文件与数据会被删除，无法恢复。')) return;
      api('/api/apps/delete', { method: 'POST', body: JSON.stringify({ appId: app.appId }) })
        .then(function () {
          toast('已卸载');
          closeSheet();
          loadApps();
          loadMeta().catch(function () {});
        })
        .catch(function (e) { toast(e.message); });
    });
  }

  function showInfoSheet() {
    var meta = state.meta;
    if (!meta) { toast('还没连上设备'); return; }
    openSheet('Kinter 信息', '' +
      '<div class="info-grid">' +
      '<div class="k">版本</div><div class="v">' + esc(meta.version) + '</div>' +
      '<div class="k">设备</div><div class="v">' + esc(meta.device) + '</div>' +
      '<div class="k">系统</div><div class="v">' + esc(meta.system) + '</div>' +
      '<div class="k">会话</div><div class="v">' + esc(meta.sessionName) + '</div>' +
      '<div class="k">服务地址</div><div class="v">' + esc(meta.baseURL) + '</div>' +
      '<div class="k">已装应用</div><div class="v">' + esc(meta.installedApps) + '</div>' +
      '<div class="k">可用能力</div><div class="v">' + esc(meta.capabilityCount) + '</div>' +
      '</div>');
  }

  // ---------------- 商店 ----------------
  function loadStore() {
    return api('/api/store').then(renderStore).catch(function (e) { toast(e.message); });
  }

  function renderStore(body) {
    var s = body.store || { sources: [], apps: [] };
    $('storeSources').innerHTML = s.sources.length ? s.sources.map(function (src) {
      return '<div class="source-row">' +
        '<div><div>' + esc(src.name) + (src.lastError ? ' <span style="color:var(--red)">· 拉取失败</span>' : '') + '</div>' +
        '<div class="source-url">' + esc(src.url) + '</div></div>' +
        '<button class="source-btn" data-remove="' + esc(src.url) + '">移除</button>' +
      '</div>';
    }).join('') : '<div class="row-line sub">还没有添加源。填入一个 index.json 地址即可。</div>';

    $('storeSources').querySelectorAll('[data-remove]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        api('/api/store/source/remove', { method: 'POST', body: JSON.stringify({ url: btn.dataset.remove }) })
          .then(renderStore).catch(function (e) { toast(e.message); });
      });
    });

    $('storeEmpty').hidden = (s.apps || []).length > 0;
    $('storeList').innerHTML = (s.apps || []).map(function (a) {
      return '<div class="card"><div class="app-row">' +
        '<div class="app-icon">' + (a.iconURL ? '<img src="' + esc(a.iconURL) + '" alt="">' : esc(a.name.slice(0, 1))) + '</div>' +
        '<div class="row-main">' +
          '<div class="row-title">' + esc(a.name) + ' <span class="dim" style="font-size:12px">v' + esc(a.version) + '</span>' +
            (a.updateAvailable ? '<span class="badge">可更新</span>' : '') + '</div>' +
          '<div class="row-meta">' + esc(a.subtitle || a.description || a.sourceName || '') + '</div>' +
        '</div>' +
        '<div class="app-actions">' +
          (a.installed && !a.updateAvailable
            ? '<button class="app-btn" data-open="' + esc(a.appId) + '">打开</button>'
            : '<button class="app-btn solid" data-install="' + esc(a.appId) + '">' +
                (a.updateAvailable ? '更新' : (a.price > 0 ? '¥' + a.price : '获取')) + '</button>') +
        '</div>' +
      '</div></div>';
    }).join('');

    $('storeList').querySelectorAll('[data-install]').forEach(function (btn) {
      btn.addEventListener('click', function () { installFromStore(btn.dataset.install, btn); });
    });
    $('storeList').querySelectorAll('[data-open]').forEach(function (btn) {
      btn.addEventListener('click', function () { openApp(btn.dataset.open); });
    });
  }

  $('addSource').addEventListener('click', function () {
    var url = $('newSource').value.trim();
    if (!url) { toast('先填写 index.json 地址'); return; }
    api('/api/store/source', { method: 'POST', body: JSON.stringify({ url: url }) })
      .then(function (body) { $('newSource').value = ''; renderStore(body); toast('已添加源'); })
      .catch(function (e) { toast(e.message); });
  });

  $('refreshStore').addEventListener('click', function () {
    toast('正在刷新…');
    api('/api/store/refresh', { method: 'POST', body: '{}' })
      .then(renderStore).catch(function (e) { toast(e.message); });
  });

  function installFromStore(appId, btn) {
    btn.disabled = true;
    btn.textContent = '安装中…';
    api('/api/store/install', { method: 'POST', body: JSON.stringify({ appId: appId }) })
      .then(function (res) {
        toast('已安装 ' + res.name);
        loadStore();
        loadApps();
      })
      .catch(function (e) {
        toast(e.message);
        btn.disabled = false;
        btn.textContent = '重试';
      });
  }

  // ---------------- 设置 ----------------
  function loadSettings() {
    return api('/api/settings').then(function (body) {
      var s = body.settings;
      state.settings = s;
      $('securityMode').checked = !!s.securityMode;
      $('webUrl').textContent = s.baseURL || '未开启';
      $('webPort').value = s.port;
      $('webToken').textContent = (s.token || '').slice(0, 6) + '••••••' + (s.token || '').slice(-4);
      $('webToken').dataset.full = s.token || '';
      $('launchMode').value = s.launchMode;
      $('confirmInstallSetting').checked = !!s.confirmInstall;
      $('showWarnings').checked = !!s.showWarnings;
      $('allowAccount').checked = !!s.allowAppsAccessAccount;
      $('authServerURL').value = s.authServerURL || '';
      $('customAppId').value = s.customAppId || '';
      $('customParams').value = s.customParams || '';
      toggleCustomRows(s.launchMode);
      return s;
    }).catch(function (e) {
      toast(e.message);
    });
  }

  function toggleCustomRows(mode) {
    var custom = mode === 'custom';
    $('customAppRow').hidden = !custom;
    $('customParamsRow').hidden = !custom;
  }

  $('launchMode').addEventListener('change', function () {
    toggleCustomRows(this.value);
  });

  $('saveSettings').addEventListener('click', function () {
    var payload = {
      securityMode: $('securityMode').checked,
      launchMode: $('launchMode').value,
      customAppId: $('customAppId').value.trim(),
      customParams: $('customParams').value.trim(),
      confirmInstall: $('confirmInstallSetting').checked,
      showWarnings: $('showWarnings').checked,
      allowAppsAccessAccount: $('allowAccount').checked,
      authServerURL: $('authServerURL').value.trim(),
      port: parseInt($('webPort').value, 10) || 0
    };
    api('/api/settings', { method: 'POST', body: JSON.stringify(payload) })
      .then(function (res) {
        state.settings = res.settings;
        toast(res.portChanged ? '设置已保存，端口变更中…' : '设置已保存');
        if (res.portChanged && res.newURL) {
          setTimeout(function () {
            toast('服务已换到 ' + res.newURL + '，请重新打开', 5000);
          }, 900);
        }
        loadMeta().catch(function () {});
      })
      .catch(function (e) { toast(e.message); });
  });

  $('webToken').addEventListener('click', function () {
    var full = $('webToken').dataset.full;
    if (!full) return;
    if (navigator.clipboard) {
      navigator.clipboard.writeText(full).then(function () { toast('令牌已复制'); })
        .catch(function () { toast('复制失败，请到 App 内查看'); });
    } else {
      toast('当前环境不支持自动复制');
    }
  });

  $('rotateToken').addEventListener('click', function () {
    if (!confirm('重新生成令牌？所有已打开的页面和旧链接都会失效，需要用新令牌重新打开。')) return;
    var btn = this;
    btn.disabled = true;
    api('/api/token/rotate', { method: 'POST', body: '{}' })
      .then(function (res) {
        store.token = res.token;
        $('webToken').textContent = (res.token || '').slice(0, 6) + '••••••' + (res.token || '').slice(-4);
        $('webToken').dataset.full = res.token || '';
        $('tokenInput').value = '';
        if (state.meta) {
          state.meta.accessURL = res.accessURL;
          renderInfo(state.meta);
        }
        toast('已生成新令牌，旧链接立刻失效');
      })
      .catch(function (e) { toast(e.message); })
      .then(function () { btn.disabled = false; });
  });

  $('saveToken').addEventListener('click', function () {
    var value = $('tokenInput').value.trim();
    if (!value) { toast('先粘贴令牌'); return; }
    store.token = value;
    toast('令牌已保存');
    loadMeta().then(function () {
      loadApps();
      if (state.currentTab === 'settings') loadSettings();
    }).catch(function () {});
  });

  $('loadAudit').addEventListener('click', function () {
    api('/api/audit?limit=40').then(function (body) {
      $('audit').textContent = (body.lines || []).join('\n') || '暂无记录';
    }).catch(function (e) { $('audit').textContent = e.message; });
  });

  // ---------------- 注销 ----------------
  function showLoggedOut() {
    loggedOut = true;
    store.token = '';
    try { document.cookie = 'kinter_web=; Path=/; Max-Age=0'; } catch (e) {}
    $('app').style.display = 'none';
    $('loggedOutScreen').hidden = false;
  }

  $('logoutWeb').addEventListener('click', function () {
    if (!confirm('退出 Web 控制？本页会立即失效，并在设备上更换新令牌。')) return;
    var btn = this;
    btn.disabled = true;
    api('/api/logout', { method: 'POST', body: '{}' })
      .then(function () { showLoggedOut(); })
      .catch(function (e) { btn.disabled = false; toast(e.message); });
  });

  // ---------------- 自动刷新 ----------------
  var refreshTimer = null;
  function scheduleRefresh() {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      loadMeta().catch(function () {});
      if (state.currentTab === 'library') loadApps();
      if (state.currentTab === 'store') loadStore();
    }, 250);
  }

  $('refreshApps').addEventListener('click', function () {
    var btn = this;
    btn.disabled = true;
    loadApps().then(function () { btn.disabled = false; })
               .catch(function () { btn.disabled = false; });
  });

  // 设备上的导入 / 卸载 / 商店安装都会广播 library.changed
  (function watchLibrary() {
    var since = 0;
    function tick() {
      if (loggedOut) return;
      api('/api/poll?since=' + since + '&wait=15&appId=kinter.webaccess')
        .then(function (body) {
          if (body.seq) since = body.seq;
          var changed = (body.events || []).some(function (ev) { return ev.event === 'library.changed'; });
          if (changed) scheduleRefresh();
          setTimeout(tick, 300);
        })
        .catch(function () {
          setTimeout(tick, 5000);
        });
    }
    tick();
  })();

  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) scheduleRefresh();
  });

  // ---------------- PWA ----------------
  var installPrompt = null;

  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault();
    installPrompt = e;
    var hint = $('pwaHint');
    if (hint) hint.textContent = '浏览器已就绪，点「安装」即可把控制台装到桌面。';
  });

  window.addEventListener('appinstalled', function () {
    installPrompt = null;
    toast('已安装到桌面');
  });

  if ('serviceWorker' in navigator) {
    var canSW = location.protocol === 'https:' ||
                location.hostname === 'localhost' ||
                location.hostname === '127.0.0.1';
    if (canSW) {
      navigator.serviceWorker.register('/sw.js').then(function () {
        var hint = $('pwaHint');
        if (hint && !installPrompt) hint.textContent = '外壳已可离线缓存；浏览器支持时会显示「安装到桌面」。';
      }).catch(function () { /* HTTP 局域网地址不支持 SW，忽略 */ });
    }
  }

  $('installPWA').addEventListener('click', function () {
    if (installPrompt) {
      installPrompt.prompt();
      installPrompt.userChoice.then(function () { installPrompt = null; });
      return;
    }
    var standalone = window.matchMedia('(display-mode: standalone)').matches ||
                     window.navigator.standalone === true;
    if (standalone) { toast('已经在独立窗口运行'); return; }
    toast('iPhone 请在 Safari 分享菜单里选「添加到主屏幕」', 4200);
  });

  // ---------------- 启动 ----------------
  function boot() {
    if (!store.token && !qs.get('token')) {
      // 没有令牌也能看导入页，但接口会 401；先给出提示
      toast('请先到「设置 → Web 访问」复制令牌填入', 4000);
    }
    switchTab(store.tab || 'import');
    loadMeta().catch(function () {});
  }

  boot();
})();
