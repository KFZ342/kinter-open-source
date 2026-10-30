# KTML 模板语法

KTML 在浏览器内由 `SDK/ktml.js` 编译为 DOM。

## 基本结构

```xml
<column padding="16" gap="12">
  <text size="xxl" weight="bold">{{ title }}</text>
  <for each="item in items" key="id">
    <row bg="surface" radius="md" padding="12">
      <text>{{ item.name }}</text>
    </row>
  </for>
</column>
<script>
var title = '水果';
var items = [{id:1, name:'苹果'}];
</script>
```

`<script>` 顶层变量会自动作为模板 data 注入。

## 语义标签（属性即样式）

| 标签 | 渲染 |
|---|---|
| box | div |
| text | span |
| card | div（白底圆角14px） |
| row | flex 横向居中 |
| column | flex 纵向 |
| scroll | overflow:auto |

别名：image→img、list→ul、item→li、link→a。
其余 HTML 标签原样透传，属性不进样式。

## 样式 token

- **size**：xs=12 / sm=14 / md=16 / lg=18 / xl=22 / xxl=28
- **weight**：regular/medium/semibold/bold
- **space**：0/4/8/12/16/20/24/32
- **radius**：none/sm=6/md=10/lg=14/xl=20/full
- **color**：primary=#007aff / success=#34c759 / danger=#ff3b30 / warning=#ff9500 / surface=#fff / background=#f2f2f7 / text=#1c1c1e / muted=#8e8e93 / border=#d1d1d6

## 属性即样式

`padding/px/py/margin/mx/my/radius/bg/color/size/weight/align/flex/width/height/gap/wrap/center/hidden`

## 插值

`{{ 表达式 }}` 自动做 HTML 转义（`& < > " '`）。
支持 `{{ a > b ? '大' : '小' }}`、`{{ items.length }}`。
字面量 `{{` 写 `\{{`。

## 控制流

```xml
<if test="loggedIn">
  <text>你好 {{ user.name }}</text>
</if>
<else>
  <text>请登录</text>
</else>

<for each="item in items" key="id">
  <text>{{ item.name }}（第 {{ __index }} 个）</text>
</for>
```

## 事件绑定

`@tap`→onclick、`@input`→oninput、`@change`→onchange、`@focus`、`@blur`。

```xml
<button @tap="handleTap('a')">按钮</button>
```

## 安全说明

**KTML 不是安全边界**：表达式与页面脚本同权。真正的权限边界是宿主能力网关（manifest + 级别 + 系统权限）。
