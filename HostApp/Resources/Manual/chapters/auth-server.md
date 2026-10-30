# 账号服务端接口

## 启动

```bash
PORT=8787 DATA_DIR=./data node server.js
```

依赖 Node.js 18+（内置 fetch/crypto），零第三方依赖。

## 存储

- `data/db.json`：用户、token、应用、购买记录
- `data/apps/{userId}/{appId}/`：发布的 ZIP

适合小规模部署。**生产环境建议换 PostgreSQL + Redis**，当前 JSON 文件在并发下会成为瓶颈。

## 接口一览

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/register` | 注册，返回 token |
| POST | `/api/login` | 登录，返回 token |
| GET | `/api/me` | 查询当前用户（Bearer token） |
| POST | `/api/logout` | 注销，删除 token |
| POST | `/api/apps/publish` | 发布应用（上传 ZIP） |
| GET | `/api/apps/mine` | 我发布的应用 |
| DELETE | `/api/apps/:appId` | 删除应用 |
| POST | `/api/apps/purchase` | 购买付费应用 |
| GET | `/api/apps/owned` | 我的已购列表 |
| GET | `/store/:username/index.json` | 商店索引 |
| GET | `/store/:username/apps/:appId/:filename` | 下载 ZIP |
| GET | `/healthz` | 健康检查 |

## 认证设计

- 密码：`scrypt(password, salt, 64)` 哈希，salt 随机 16 字节
- Token：随机 32 字节 hex，有效期 30 天
- **登录时即使用户不存在也执行一次 scrypt**（用假 salt），拉平耗时，防时序攻击

## 安全要求（生产环境）

- 必须 HTTPS（当前裸 HTTP 仅供内网测试）
- 密码必须哈希加盐（已实现）
- Token 定期过期（30 天）
- ZIP 解包防路径穿越与炸弹（已实现）
- 建议加 rate limiting（当前未实现）

## 客户端配置

宿主「设置 → 账号」里填服务器地址。默认空时不可用，需自行部署。
