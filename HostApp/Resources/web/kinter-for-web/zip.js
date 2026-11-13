/* 轻量 ZIP 读取：支持 stored / deflate，够用来导入小程序安装包。
   不依赖第三方库，使用浏览器自带的 DecompressionStream('deflate-raw')。
   安全加固：路径白名单校验、偏移/长度边界检查、CRC32 校验、解压炸弹阈值、
   条目数量/深度/重名限制、UTF-8 标志位处理。 */
(function (global) {
  'use strict';

  var SIG_EOCD = 0x06054b50;
  var SIG_CENTRAL = 0x02014b50;
  var SIG_LOCAL = 0x04034b50;

  /* ---------- 安全上限 ---------- */
  var MAX_ENTRIES = 5000;          // 条目总数上限
  var MAX_DEPTH = 16;              // 目录嵌套深度上限
  var MAX_TOTAL_OUT = 40 * 1024 * 1024;  // 解压后总大小 40 MB
  var MAX_ENTRY_RAW = 20 * 1024 * 1024;  // 单文件解压后 20 MB
  var MAX_COMP_SIZE = 25 * 1024 * 1024;  // 单条目压缩数据 25 MB
  var MAX_RATIO = 200;             // 解压/压缩 比阈值（炸弹判定）
  var MAX_NAME_LEN = 300;
  var MAX_SEG_LEN = 128;
  var FLAG_ENCRYPTED = 0x0001;
  var FLAG_UTF8 = 0x0800;

  /* ---------- CRC32 ---------- */
  var CRC_TABLE = (function () {
    var t = new Uint32Array(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      t[n] = c >>> 0;
    }
    return t;
  })();

  function crc32(u8) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < u8.length; i++) {
      crc = CRC_TABLE[(crc ^ u8[i]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  /* ---------- 文件名解码 ---------- */
  function cp437Decode(bytes) {
    var map = [
      '\u00c7', '\u00fc', '\u00e9', '\u00e2', '\u00e4', '\u00e0', '\u00e5', '\u00e7',
      '\u00ea', '\u00eb', '\u00e8', '\u00ef', '\u00ee', '\u00ec', '\u00c4', '\u00c5',
      '\u00c6', '\u00e6', '\u00f4', '\u00f6', '\u00f2', '\u00fb', '\u00f9', '\u00ff',
      '\u00d6', '\u00dc', '\u00a2', '\u00a3', '\u00a5', '\u20a7', '\u0192', '\u00e1',
      '\u00ed', '\u00f3', '\u00fa', '\u00f1', '\u00d1', '\u00a1', '\u00bf', '\u00ae',
      '\u00ae', '\u2122', '\u00a2', '\u00a5', '\u0192', '\u00a1', '\u00bf', '\u2310',
      '\u00ac', '\u00bd', '\u00bc', '\u00a1', '\u00ab', '\u00bb', '\u2591', '\u2592',
      '\u2593', '\u2502', '\u2524', '\u2502', '\u2510', '\u2514', '\u2534', '\u2518',
      '\u252c', '\u2500', '\u253c', '\u2590', '\u2588', '\u2584', '\u258c', '\u2590',
      '\u2580', '\u03b1', '\u00df', '\u0393', '\u03c0', '\u03a3', '\u03c3', '\u00bc',
      '\u00ac', '\u2310', '\u03b4', '\u2219', '\u00f7', '\u221e', '\u03b8', '\u03b5',
      '\u2229', '\u2261', '\u00b1', '\u2265', '\u2264', '\u2320', '\u2321', '\u00f7',
      '\u2248', '\u00b0', '\u2219', '\u00b7', '\u221a', '\u207f', '\u00b2', '\u25a0'
    ];
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      var b = bytes[i];
      out += b < 0x80 ? String.fromCharCode(b) : map[b - 0x80] || String.fromCharCode(b);
    }
    return out;
  }

  function decodeName(bytes, flags) {
    var name;
    if (flags & FLAG_UTF8) {
      try { name = new TextDecoder('utf-8', { fatal: false }).decode(bytes); }
      catch (e) { name = cp437Decode(bytes); }
    } else {
      name = cp437Decode(bytes);
    }
    try { return name.normalize('NFC'); } catch (e) { return name; }
  }

  /* ---------- 路径白名单校验 ---------- */
  function sanitizeName(rawName) {
    var name = String(rawName == null ? '' : rawName).replace(/\\/g, '/');
    if (!name) throw new Error('ZIP 条目文件名为空');
    // 控制字符 / NUL
    if (/[\u0000-\u001f\u007f]/.test(name)) throw new Error('文件名含非法控制字符：' + name);
    // 绝对路径
    if (name.charAt(0) === '/') throw new Error('拒绝绝对路径条目：' + name);
    // Windows 盘符
    if (/^[A-Za-z]:/.test(name)) throw new Error('拒绝盘符路径条目：' + name);

    var segs = name.split('/');
    var out = [];
    for (var i = 0; i < segs.length; i++) {
      var seg = segs[i];
      if (seg === '' || seg === '.') throw new Error('文件名含空段或当前目录段：' + name);
      if (seg === '..') throw new Error('拒绝路径穿越条目：' + name);
      if (/[?*"<>|:]/.test(seg)) throw new Error('文件名含非法字符：' + seg);
      if (seg.length > MAX_SEG_LEN) throw new Error('路径段过长：' + seg);
      out.push(seg);
    }
    if (!out.length) throw new Error('ZIP 条目文件名为空');
    if (out.length > MAX_DEPTH) throw new Error('目录嵌套过深（上限 ' + MAX_DEPTH + ' 层）');
    var normalized = out.join('/');
    if (normalized.length > MAX_NAME_LEN) throw new Error('文件路径过长：' + normalized);
    return normalized;
  }

  /* ---------- EOCD 定位（带边界与注释长度校验） ---------- */
  function findEOCD(dv, len) {
    var start = Math.max(0, len - 65558);
    for (var i = len - 22; i >= start; i--) {
      if (i + 22 > len) continue;
      if (dv.getUint32(i, true) !== SIG_EOCD) continue;
      var commentLen = dv.getUint16(i + 20, true);
      if (i + 22 + commentLen !== len) continue; // 注释长度不匹配，跳过伪命中
      return i;
    }
    return -1;
  }

  /* ---------- 流式解压，输出长度硬上限 ---------- */
  async function inflateRawLimited(bytes, rawSize) {
    if (typeof DecompressionStream === 'undefined') {
      throw new Error('当前浏览器不支持解压 ZIP，请使用 Safari 16.4+ 或现代 Chrome / Edge');
    }
    var cap = Math.max(rawSize, MAX_ENTRY_RAW);
    var stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    var reader = stream.getReader();
    var chunks = [];
    var total = 0;
    while (true) {
      var r = await reader.read();
      if (r.done) break;
      var chunk = r.value;
      total += chunk.length;
      if (total > cap) {
        try { reader.cancel(); } catch (e) {}
        throw new Error('解压输出超过单文件上限（疑似压缩炸弹）');
      }
      chunks.push(chunk);
    }
    var out = new Uint8Array(total);
    var o = 0;
    chunks.forEach(function (c) { out.set(c, o); o += c.length; });
    return out;
  }

  async function unzip(arrayBuffer) {
    var dv = new DataView(arrayBuffer);
    var len = arrayBuffer.byteLength;
    if (len < 22) throw new Error('不是有效的 ZIP：文件过小');

    var eocd = findEOCD(dv, len);
    if (eocd < 0) throw new Error('不是有效的 ZIP：找不到目录结尾');
    if (eocd + 22 > len) throw new Error('ZIP 目录结尾越界');

    var total = dv.getUint16(eocd + 10, true);
    var cdSize = dv.getUint32(eocd + 12, true);
    var cdOffset = dv.getUint32(eocd + 16, true);
    if (cdOffset + cdSize > len) throw new Error('ZIP 中央目录越界');
    if (total === 0) throw new Error('安装包是空的');
    if (total > MAX_ENTRIES) throw new Error('安装包条目过多（上限 ' + MAX_ENTRIES + '）');

    var offset = cdOffset;
    var files = {};
    var seen = {};
    var totalOut = 0;

    for (var n = 0; n < total; n++) {
      if (offset + 46 > len) throw new Error('ZIP 中央目录损坏：条目越界');
      if (dv.getUint32(offset, true) !== SIG_CENTRAL) throw new Error('ZIP 中央目录签名错误');

      var flags = dv.getUint16(offset + 8, true);
      var method = dv.getUint16(offset + 10, true);
      var crc = dv.getUint32(offset + 16, true);
      var compSize = dv.getUint32(offset + 20, true);
      var rawSize = dv.getUint32(offset + 24, true);
      var nameLen = dv.getUint16(offset + 28, true);
      var extraLen = dv.getUint16(offset + 30, true);
      var commentLen = dv.getUint16(offset + 32, true);
      var localOffset = dv.getUint32(offset + 42, true);

      var entryEnd = offset + 46 + nameLen + extraLen + commentLen;
      if (entryEnd > len) throw new Error('ZIP 中央目录条目越界');
      if (nameLen <= 0 || nameLen > MAX_NAME_LEN) throw new Error('文件名长度非法');

      var nameBytes = new Uint8Array(arrayBuffer, offset + 46, nameLen);
      var rawName = decodeName(nameBytes, flags);

      if (flags & FLAG_ENCRYPTED) throw new Error('不支持加密 ZIP：' + rawName);
      if (method !== 0 && method !== 8) {
        throw new Error('不支持的 ZIP 压缩方式：' + method + '（' + rawName + '）');
      }

      // 本地文件头边界校验
      if (localOffset + 30 > len) throw new Error('ZIP 本地文件头越界：' + rawName);
      if (dv.getUint32(localOffset, true) !== SIG_LOCAL) throw new Error('ZIP 本地文件头签名错误：' + rawName);
      var lNameLen = dv.getUint16(localOffset + 26, true);
      var lExtraLen = dv.getUint16(localOffset + 28, true);
      var dataStart = localOffset + 30 + lNameLen + lExtraLen;
      if (dataStart + compSize > len) throw new Error('ZIP 数据段越界：' + rawName);

      // 目录条目：不落地
      if (rawName.charAt(rawName.length - 1) === '/') {
        offset = entryEnd;
        continue;
      }

      // 大小与压缩炸弹阈值
      if (rawSize > MAX_ENTRY_RAW) throw new Error('单个文件过大：' + rawName);
      if (compSize > MAX_COMP_SIZE) throw new Error('单个条目压缩数据过大：' + rawName);
      if (method === 8 && compSize === 0 && rawSize > 0) {
        throw new Error('压缩数据为空但声明非空：' + rawName);
      }
      if (method === 8 && compSize > 0 && rawSize / compSize > MAX_RATIO) {
        throw new Error('压缩比异常（疑似解压炸弹）：' + rawName);
      }

      var name = sanitizeName(rawName);
      if (seen[name]) throw new Error('安装包内存在重名文件：' + name);
      seen[name] = true;

      var raw = new Uint8Array(arrayBuffer, dataStart, compSize);
      var data;
      if (method === 0) {
        if (raw.length !== rawSize) throw new Error('存储条目大小与声明不一致：' + name);
        data = raw;
      } else {
        data = await inflateRawLimited(raw, rawSize);
        if (data.length !== rawSize) throw new Error('解压长度与声明不一致：' + name);
      }

      // CRC32 校验；crc 为 0（数据描述符模式）时跳过
      if (crc !== 0 && crc32(data) !== crc) throw new Error('CRC 校验失败：' + name);

      totalOut += data.length;
      if (totalOut > MAX_TOTAL_OUT) throw new Error('安装包解压后超过 40 MB');
      files[name] = data;
      offset = entryEnd;
    }
    return files;
  }

  global.KinterZIP = { unzip: unzip, sanitizeName: sanitizeName };
})(window);
