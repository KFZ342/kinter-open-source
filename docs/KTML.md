# KTML 模板语法

KTML 是 Kinter 的声明式页面模板，语法大部分继承 HTML，额外提供插值、控制流、样式 token 与事件绑定。模板在**浏览器内**由 `SDK/ktml.js` 编译为 DOM。

## 基本结构

一个 `.ktml` 文件 = 模板 + `<script>`（脚本提供的顶层变量即模板数据）：

```
<column padding="16" gap="12">
  <text size="xxl" weight="bold">{{ title }}</text>
  <for each="item in items" key="id">
    <row bg="surface" radius="md" padding="12">
      <text>{{ item.name }}</text>
      <text color="muted">{{ item.price }}</text>
    </row>
  </for>
</column>

<script>
var title = '水果';
var items = [
  { id: 1, name: '苹果', price: '¥8.5' },
  { id: 2, name: '香蕉', price: '¥5.0' }
];
</script>
```

`<script>` 块在宿主内先于渲染执行，其中**顶层声明的变量/函数会作为模板 data 注入**。

## 标签

### 语义标签（有默认样式 + 属性即样式）

| 标签 | 渲染为 | 默认样式 |
|---|---|---|
| `box` | div | display:block |
| `text` | span | display:inline |
| `card` | div | 白底、圆角 14px、内边距 16px |
| `row` | div | display:flex; 垂直居中 |
| `column` | div | display:flex; 纵向排列 |
| `scroll` | div | overflow:auto |

### 别名（映射到 HTML 标签，无属性即样式）

`image`→img、`list`→ul、`item`→li、`link`→a

### 标准 HTML 标签

`div / span / img / input / button / a / ul / li / br` 等一律**按 HTML 原样透传**，属性不被 KTML 吃掉（如 `width`、`size`、`color` 保留 HTML 语义）。

> 规则：只有 `box / text / card / row / column / scroll` 六个语义标签应用「属性即样式」；其余标签属性直接进 DOM。

## 样式 token

属性值支持设计 token（也接受任意 CSS 值，token 未命中时原样使用）：

| token | 取值 |
|---|---|
| size（字号） | xs=12px · sm=14px · md=16px · lg=18px · xl=22px · xxl=28px |
| weight（字重） | regular=400 · medium=500 · semibold=600 · bold=700 |
| space（间距，padding/margin/gap） | 0 · 4 · 8 · 12 · 16 · 20 · 24 · 32（px） |
| radius（圆角） | none · sm=6px · md=10px · lg=14px · xl=20px · full=9999px |
| color（颜色） | primary=#007aff · success=#34c759 · danger=#ff3b30 · warning=#ff9500 · surface=#fff · background=#f2f2f7 · text=#1c1c1e · muted=#8e8e93 · border=#d1d1d6 |

## 属性即样式（仅语义标签）

| 属性 | 生成的 CSS |
|---|---|
| `padding` | padding |
| `px` | padding-left + padding-right |
| `py` | padding-top + padding-bottom |
| `margin` / `mx` / `my` | margin / 左右 / 上下 |
| `radius` | border-radius |
| `bg` | background |
| `color` | color |
| `size` | font-size |
| `weight` | font-weight |
| `align` | text-align |
| `flex` | display:flex; flex:值 |
| `width` / `height` | 纯数字自动加 px |
| `gap` | gap |
| `wrap` | flex-wrap:wrap |
| `center` | flex 居中 |
| `hidden` | display:none |

## 插值

`{{ 表达式 }}` 输出表达式结果，**自动做 HTML 实体转义**（`& < > " '`），不可信数据不会注入 HTML/脚本。

- `{{ title }}`、`{{ item.price }}`、`{{ items.length }}`、`{{ a > b ? '大' : '小' }}`
- 表达式在页面全局作用域内求值（`with` 限定 data 优先），可访问脚本声明的变量
- 需要字面量 `{{` 时写 `\{{`

## 控制流

### if / else

```
<if test="loggedIn">
  <text>你好，{{ user.name }}</text>
</if>
<else>
  <text>请登录</text>
</else>
```

条件也可用 `cond` 或 `each` 属性名（兼容）。

### for

```
<for each="item in items" key="id">
  <text>{{ item.name }}（第 {{ __index }} 个）</text>
</for>
```

- `each` 语法：`别名 in 表达式`；表达式返回数组
- `key` 指定唯一键（用于后续 diff，当前仅作标识）
- 循环内可用 `__index` 取索引

## 事件绑定

`@事件="JS 表达式"` → 映射为 DOM 事件：

| KTML | DOM |
|---|---|
| `@tap` | onclick |
| `@input` | oninput |
| `@change` | onchange |
| `@focus` | onfocus |
| `@blur` | onblur |

```
<button @tap="handleTap('a')">按钮</button>
<text @tap="count = count + 1">点我</text>
```

事件处理函数定义在 `<script>` 顶层（作为全局函数）。

## 宿主 API（ktml.js 暴露 `window.KTML`）

| 方法 | 说明 |
|---|---|
| `KTML.compile(source)` | 编译模板为 HTML 字符串 |
| `KTML.render(source, data)` | 用数据渲染模板 |
| `KTML.renderInto(target, source, data)` | 渲染到指定 DOM 元素 |
| `KTML.mount(container)` | 在容器内原地解析（优先 `<template id="ktml-source">`） |
| `KTML.toStandaloneHTML(source)` | 生成可独立在浏览器打开的完整 HTML 文档（本地预览用） |

## 安全说明

- 插值默认转义，`<script>` 内字符串插值到 DOM 不会执行
- **KTML 不是安全边界**：表达式与页面脚本同权，可访问全局；真正的权限边界是宿主的能力网关（manifest 声明 + 级别 + 系统权限）。不要让模板渲染承担可执行代码隔离职责。

## 本地预览

```bash
# 把 index.ktml 转成独立 HTML 在浏览器打开
# （ktml.js 提供 KTML.toStandaloneHTML，可在控制台或小工具里调用）
```

宿主内调试：直接在宿主「导入」里选择 ktml-test 示例即可。
