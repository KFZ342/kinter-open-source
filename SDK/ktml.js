/*
 * KTML 编译器
 *
 * 语法大部分继承 HTML，额外支持：
 *   - {{ 表达式 }} 插值
 *   - <if test="cond">...</if>  /  <else>...</else>
 *   - <for each="item in items" key="id">...</for>
 *   - 属性即样式：padding / radius / bg / color / size / weight ...
 *   - 事件绑定：@tap / @input / @change → onclick / oninput / onchange
 *
 * 用法：
 *   const html = KTML.compile(source)
 *   或者 DOM 内容：KTML.mount(container, source, data)
 */
(function (root) {
  'use strict';

  // ============ 1. 样式 token 映射 ============

  // 设计 token：属性值 -> CSS 值
  var SIZE_TOKENS = {
    xs: '12px', sm: '14px', md: '16px', lg: '18px', xl: '22px', xxl: '28px'
  };
  var WEIGHT_TOKENS = {
    regular: '400', medium: '500', semibold: '600', bold: '700'
  };
  var SPACE_TOKENS = {
    0: '0', 4: '4px', 8: '8px', 12: '12px', 16: '16px', 20: '20px', 24: '24px', 32: '32px'
  };
  var RADIUS_TOKENS = {
    none: '0', sm: '6px', md: '10px', lg: '14px', xl: '20px', full: '9999px'
  };
  var COLOR_TOKENS = {
    primary: '#007aff', success: '#34c759', danger: '#ff3b30', warning: '#ff9500',
    surface: '#ffffff', background: '#f2f2f7', text: '#1c1c1e',
    muted: '#8e8e93', border: '#d1d1d6'
  };

  // 属性名 -> CSS 映射
  var ATTR_TO_CSS = {
    padding: function (v) { return 'padding:' + (SPACE_TOKENS[v] || v); },
    px: function (v) { return 'padding-left:' + (SPACE_TOKENS[v] || v) + ';padding-right:' + (SPACE_TOKENS[v] || v); },
    py: function (v) { return 'padding-top:' + (SPACE_TOKENS[v] || v) + ';padding-bottom:' + (SPACE_TOKENS[v] || v); },
    margin: function (v) { return 'margin:' + (SPACE_TOKENS[v] || v); },
    mx: function (v) { return 'margin-left:' + (SPACE_TOKENS[v] || v) + ';margin-right:' + (SPACE_TOKENS[v] || v); },
    my: function (v) { return 'margin-top:' + (SPACE_TOKENS[v] || v) + ';margin-bottom:' + (SPACE_TOKENS[v] || v); },
    radius: function (v) { return 'border-radius:' + (RADIUS_TOKENS[v] || v); },
    bg: function (v) { return 'background:' + (COLOR_TOKENS[v] || v); },
    color: function (v) { return 'color:' + (COLOR_TOKENS[v] || v); },
    size: function (v) { return 'font-size:' + (SIZE_TOKENS[v] || v); },
    weight: function (v) { return 'font-weight:' + (WEIGHT_TOKENS[v] || v); },
    align: function (v) { return 'text-align:' + v; },
    flex: function (v) { return 'display:flex;flex:' + v; },
    width: function (v) { return 'width:' + (/^\d+$/.test(v) ? v + 'px' : v); },
    height: function (v) { return 'height:' + (/^\d+$/.test(v) ? v + 'px' : v); },
    gap: function (v) { return 'gap:' + (SPACE_TOKENS[v] || v); },
    wrap: function () { return 'flex-wrap:wrap'; },
    center: function () { return 'display:flex;align-items:center;justify-content:center'; },
    hidden: function () { return 'display:none'; }
  };

  // ============ 2. 标签别名 ============

  // 可选语义标签：把 KTML 的简写映射到 HTML 标签。
  // 不在这里的标签一律按 HTML 原样透传。
  var TAG_ALIASES = {
    box: 'div',
    text: 'span',
    card: 'div',
    row: 'div',
    column: 'div',
    image: 'img',
    scroll: 'div',
    list: 'ul',
    item: 'li',
    link: 'a'
  };

  // 只有这些纯 KTML 语义标签才应用属性即样式。
  // 标准 HTML 标签（div/img/input/button/a 等）的属性一律透传，避免吃掉 width/hidden/size/color 等 HTML 语义。
  var SEMANTIC_TAGS = ['box', 'text', 'card', 'row', 'column', 'scroll'];

  // 语义标签的默认样式
  var TAG_BASE_CSS = {
    box: 'display:block',
    text: 'display:inline',
    card: 'display:block;background:#fff;border-radius:14px;padding:16px',
    row: 'display:flex;align-items:center',
    column: 'display:flex;flex-direction:column',
    scroll: 'overflow:auto',
    list: 'list-style:none;padding:0;margin:0',
    image: 'display:block',
    button: 'cursor:pointer'
  };

  // ============ 3. 词法与 AST ============

  /**
   * 极简 HTML 解析器：只处理标签、属性、文本。
   * 不做严格容错，KTML 源码要求闭合标签正确。
   */
  function parse(source) {
    var root = { tag: '#root', attrs: {}, children: [], raw: '' };
    var stack = [root];
    var i = 0;
    var len = source.length;

    while (i < len) {
      var ch = source[i];

      // 注释
      if (ch === '<' && source.substr(i, 4) === '<!--') {
        var endComment = source.indexOf('-->', i + 4);
        i = endComment < 0 ? len : endComment + 3;
        continue;
      }

      // 闭合标签
      if (ch === '<' && source[i + 1] === '/') {
        var endTag = source.indexOf('>', i);
        if (endTag < 0) break;
        var closeName = source.substring(i + 2, endTag).trim().toLowerCase();
        // 弹栈到匹配的节点
        for (var s = stack.length - 1; s > 0; s--) {
          if (stack[s].tag === closeName) {
            stack.length = s;
            break;
          }
        }
        i = endTag + 1;
        continue;
      }

      // 开标签
      if (ch === '<' && /[a-zA-Z]/.test(source[i + 1])) {
        var gt = findTagEnd(source, i);
        if (gt < 0) break;
        var tagText = source.substring(i + 1, gt);
        var selfClose = tagText[tagText.length - 1] === '/';
        if (selfClose) tagText = tagText.slice(0, -1);

        var parsed = parseTag(tagText);
        var node = {
          tag: parsed.name,
          attrs: parsed.attrs,
          children: [],
          raw: ''
        };
        stack[stack.length - 1].children.push(node);
        if (!selfClose) stack.push(node);
        i = gt + 1;
        continue;
      }

      // 文本
      var next = source.indexOf('<', i);
      if (next < 0) next = len;
      var text = source.substring(i, next);
      if (text.trim()) {
        stack[stack.length - 1].children.push({ tag: '#text', text: text, children: [], attrs: {} });
      }
      i = next;
    }

    return root;
  }

  function findTagEnd(src, start) {
    var inQuote = null;
    for (var i = start + 1; i < src.length; i++) {
      var c = src[i];
      if (inQuote) {
        if (c === inQuote) inQuote = null;
      } else if (c === '"' || c === "'") {
        inQuote = c;
      } else if (c === '>') {
        return i;
      }
    }
    return -1;
  }

  function parseTag(text) {
    // text 形如：box padding="16" bg="surface"
    var m = text.match(/^([a-zA-Z][\w-]*)/);
    if (!m) return { name: 'div', attrs: {} };
    var name = m[1].toLowerCase();
    var rest = text.slice(name.length);
    var attrs = {};
    var re = /([\w@:-]+)(?:\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
    var am;
    while ((am = re.exec(rest))) {
      var key = am[1];
      var val = am[3] !== undefined ? am[3] : (am[4] !== undefined ? am[4] : (am[5] !== undefined ? am[5] : ''));
      attrs[key] = val;
    }
    return { name: name, attrs: attrs };
  }

  // ============ 4. 表达式求值 ============

  /**
   * 极简表达式求值。只允许访问提供的 data 对象属性。
   *
   * 注意：这里不是安全边界——表达式仍在页面全局作用域内求值（with 只
   * 改变变量解析优先序），与页面内 <script> 同权。真正的安全边界是
   * 宿主的能力网关，而不是 KTML 模板。不要把模板渲染当作可执行代码的
   * 隔离手段；把来自网络/用户输入的数据放进 {{ }} 时，插值会自动做
   * HTML 转义（见 escapeHTML），避免直接注入 HTML/脚本。
   */
  function evaluate(expr, data) {
    try {
      // 用 with 限定作用域
      var fn = new Function('__data', 'with(__data){return (' + expr + ')}');
      return fn(data || {});
    } catch (e) {
      console.warn('[KTML] 表达式求值失败:', expr, e.message);
      return '';
    }
  }

  // HTML 实体转义，防止插值把不可信数据直接渲染成 HTML/脚本。
  function escapeHTML(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // 插值：{{ expr }} -> 转义后的结果字符串
  function interpolate(str, data) {
    if (str.indexOf('{') < 0) return str;
    // 支持 \\{{ 转义为字面量 {{
    var ESC = '\u0000KTML_ESC\u0000';
    var out = str.replace(/\\\{\{/g, ESC);
    out = out.replace(/\{\{([\s\S]+?)\}\}/g, function (_, expr) {
      var v = evaluate(expr.trim(), data);
      return v == null ? '' : escapeHTML(v);
    });
    return out.replace(new RegExp(ESC, 'g'), '{{');
  }

  // ============ 5. AST → HTML ============

  function render(node, data) {
    if (node.tag === '#root') {
      return node.children.map(function (c) { return render(c, data); }).join('');
    }
    if (node.tag === '#text') {
      return interpolate(node.text, data);
    }

    // 控制流：if
    if (node.tag === 'if') {
      var cond = node.attrs.test || node.attrs.each || node.attrs.cond;
      var ok = evaluate(cond, data);
      return ok ? node.children.map(function (c) { return render(c, data); }).join('') : '';
    }

    // 控制流：else
    if (node.tag === 'else') {
      // else 由父级 if 决定是否渲染。这里简化处理：独立 else 不渲染。
      return '';
    }

    // 控制流：for
    if (node.tag === 'for') {
      var each = node.attrs.each || '';
      var m = each.match(/^\s*([\w$]+)\s+in\s+([\s\S]+)$/);
      if (!m) return '';
      var itemName = m[1];
      var listExpr = m[2];
      var list = evaluate(listExpr, data);
      if (!Array.isArray(list)) return '';
      var key = node.attrs.key;
      var out = '';
      list.forEach(function (item, idx) {
        var local = Object.assign({}, data);
        local[itemName] = item;
        local.__index = idx;
        out += node.children.map(function (c) { return render(c, local); }).join('');
      });
      return out;
    }

    // 普通标签：转换
    var tag = TAG_ALIASES[node.tag] || node.tag;
    var cssParts = [];
    var htmlAttrs = {};

    // 基础样式
    if (TAG_BASE_CSS[node.tag]) {
      cssParts.push(TAG_BASE_CSS[node.tag]);
    }

    Object.keys(node.attrs).forEach(function (k) {
      var v = node.attrs[k];
      // 样式属性：只对 KTML 语义标签生效
      if (SEMANTIC_TAGS.indexOf(node.tag) >= 0 && ATTR_TO_CSS[k]) {
        cssParts.push(ATTR_TO_CSS[k](interpolate(v, data)));
        return;
      }
      // 事件：@tap -> onclick
      if (k[0] === '@') {
        var evt = k.slice(1);
        var eventMap = { tap: 'click', input: 'input', change: 'change', focus: 'focus', blur: 'blur' };
        var domEvt = eventMap[evt] || evt;
        htmlAttrs['on' + domEvt] = v;
        return;
      }
      // 普通属性
      htmlAttrs[k] = interpolate(v, data);
    });

    // 合并 style
    if (cssParts.length) {
      htmlAttrs.style = (htmlAttrs.style ? htmlAttrs.style + ';' : '') + cssParts.join(';');
    }

    var attrStr = '';
    Object.keys(htmlAttrs).forEach(function (k) {
      var v = htmlAttrs[k];
      if (v === '' || v === true) {
        attrStr += ' ' + k;
      } else {
        // 属性值统一做 HTML 实体转义（浏览器解析属性时会解码实体，JS 代码不受影响）
        attrStr += ' ' + k + '="' + escapeHTML(v) + '"';
      }
    });

    var inner = node.children.map(function (c) { return render(c, data); }).join('');

    if (tag === 'img' || tag === 'input' || tag === 'br') {
      return '<' + tag + attrStr + '>';
    }
    return '<' + tag + attrStr + '>' + inner + '</' + tag + '>';
  }

  // ============ 6. 对外接口 ============

  function compile(source) {
    var ast = parse(source);
    return render(ast, {});
  }

  function renderWithData(source, data) {
    var ast = parse(source);
    return render(ast, data || {});
  }

  /**
   * 在 DOM 内原地解析 KTML 模板。
   * 优先使用 <template> 标签，其次用 body 内容。
   */
  function mount(container) {
    container = container || document.body;
    // 如果内部有 <template id="ktml-source">，用它的文本
    var tpl = container.querySelector('template#ktml-source');
    var source = tpl ? tpl.innerHTML : container.innerHTML;
    var html = compile(source);
    if (tpl) {
      var target = document.getElementById('ktml-root') || container;
      target.innerHTML = html;
    } else {
      container.innerHTML = html;
    }
  }

  /**
   * 编译成可直接在浏览器打开的完整 HTML 文档。
   * 用于开发者本地预览，不依赖宿主。
   */
  function toStandaloneHTML(source) {
    var body = compile(source);
    return '<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n' +
      '<meta charset="utf-8">\n' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">\n' +
      '<style>*{box-sizing:border-box}body{margin:0;padding:0;font-family:-apple-system,sans-serif}</style>\n' +
      '</head>\n<body>\n' + body + '\n</body>\n</html>';
  }

  /**
   * 运行时渲染：把模板源码用给定数据渲染到目标元素。
   * 用于编译产物在浏览器里二次渲染（数据来自用户 script）。
   */
  function renderInto(target, templateSource, data) {
    var ast = parse(templateSource);
    var html = render(ast, data || {});
    target.innerHTML = html;
    return html;
  }

  root.KTML = {
    compile: compile,
    render: renderWithData,
    renderInto: renderInto,
    mount: mount,
    toStandaloneHTML: toStandaloneHTML,
    version: '0.3.0'
  };
})(typeof window !== 'undefined' ? window : globalThis);
