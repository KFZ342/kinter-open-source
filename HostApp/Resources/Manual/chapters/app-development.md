# 从零开发一个小程序

## 目录结构

```
my-app/
├── manifest.json      必需
├── index.html         必需（或 index.ktml）
├── icon.png / icon.svg
└── pages/
    └── detail/detail.html
```

## manifest.json

```json
{
  "appId": "com.example.hello",
  "version": "1.0.0",
  "name": "示例应用",
  "pages": ["index"],
  "category": "工具",
  "description": "一句话说明",
  "capabilities": {
    "deviceInfo": { "level": "L0" },
    "files": { "level": "L0" }
  }
}
```

必填：appId（仅字母数字._-）、name、version、pages。能力声明必须在清单中，级别须与网关注册一致。

## 两种渲染方式

**HTML 方式**：直接写标准 HTML + 内联 JS，用 `wx.*` 调能力。

**KTML 方式**：声明式模板，`<script>` 顶层变量自动注入为数据，详见 KTML 章节。

## 页面路由

`pages` 数组列出所有页面（不含 .html），首项为首页。跳转：

```js
wx.navigateTo({ url: 'pages/detail/detail?id=1' });
wx.navigateBack({ delta: 1 });
```

栈深上限 10 层。

## 调试日志规范

宿主有实时日志面板，**关键流程必须打日志**：

```js
console.log('页面初始化完成');
console.error('请求失败:', err.message);
```

初始化、用户操作、请求成功/失败、状态切换处都要记。

## 禁用清单

- 禁止 `localStorage` / `sessionStorage` / `indexedDB` → 用 `wx.setStorage`
- 禁止 `XMLHttpRequest` / `fetch` → 用 `wx.request`
- 禁止 `alert` / `confirm` / `prompt` → 用 `wx.toast` / `wx.showModal`
- 禁止外部 CDN / 外链字体图片 → 全部内联或放进文件

## 打包安装

把目录压成 ZIP → 宿主「导入」选 ZIP → 自动校验 manifest → 安装到应用库。

## 发布到商店

见「商店、发布与付费」章节。核心：`POST /api/apps/publish` 上传 ZIP。
