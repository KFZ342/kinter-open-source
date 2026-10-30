# 商店、发布与付费

## 静态商店源结构

```
apps/
  app-name/
    manifest.json
    icon.png
    1.0.0.zip
index.json
```

可托管到 GitHub Pages / jsDelivr，无需复杂后端。

## index.json 格式

```json
{
  "name": "xxx 的商店",
  "identifier": "kinter.xxx",
  "subtitle": "共 N 个应用",
  "apps": [
    {
      "appId": "com.example.app",
      "name": "示例",
      "version": "1.0.0",
      "description": "...",
      "category": "工具",
      "size": 12345,
      "price": 6.0,
      "currency": "CNY",
      "downloadURL": "https://.../1.0.0.zip"
    }
  ]
}
```

`price` 缺省或 ≤0 即为免费应用。

## 发布流程

1. AI Agent 或手动调用 `POST /api/apps/publish`
2. 上传 ZIP（multipart 或 `application/zip`）
3. 服务端校验 manifest（appId 格式、必填字段）
4. 解压到 `data/apps/{userId}/{appId}/`
5. 更新 `db.json` 中的 apps 记录
6. 返回 `sourceURL`（已复制到剪贴板）

## 付费小程序

- 发布时传 `price` 字段（multipart 表单字段优先，其次 manifest.price）
- 商店展示价格，未购买用户看到「购买」按钮
- 购买后 `POST /api/apps/purchase` 记录到 `db.purchases`（幂等）
- 已购用户下载 ZIP 时携带 `Bearer token`，服务端校验购买记录
- 发布者本人可免费下载自己的付费应用

## 平台抽成

README 明确：**平台抽成 7%**。

结算口径：售价 × 85%（Apple 抽成后宿主实收）× 93%（扣除平台 7%）= 开发者应得 79.05% 售价。

## 下载鉴权

`GET /store/:username/apps/:appId/:filename`：
- 免费应用：直接返回 ZIP
- 付费应用：必须 `Authorization: Bearer <token>`，且已购买（发布者本人除外）

## 安全限制

- 文件名拒绝 `..` 和 `/`（防路径穿越）
- 解压拒绝含 `..`、绝对路径、反斜杠的条目（zip-slip 防护）
- ZIP 大小上限 50MB
- appId 仅字母数字._-
