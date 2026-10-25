# Kinter 账号 + 商店服务器部署指南

> 付费小程序必须登录账号才能购买和下载。所有鉴权都由本服务端承担：
> 购买记录存 `db.json`（`purchases`），付费 ZIP 下载校验 Bearer token + 已购记录。

## 一、服务器要求（很低）

| 项目 | 要求 |
|---|---|
| 系统 | Linux（Ubuntu 22.04+ / Debian）/ macOS 均可 |
| 内存 | **512MB 起步**（当前用量极小；商店长大后可升 1G） |
| 存储 | 10GB（ZIP 包会累积） |
| 运行时 | **Node.js 18+**（内置 fetch/crypto） |
| 网络 | 公网 IP + 开放一个端口；**必须配 HTTPS**（token 不能明文传输） |

推荐：阿里云/腾讯云轻量服务器（¥24-40/月档）、Vultr、DigitalOcean 最低配均可。

## 二、部署步骤

```bash
# 1. 装 Node 18+（Ubuntu）
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 2. 上传 AuthServer 目录到服务器（或用 git）
scp -r AuthServer user@你的服务器:/opt/kinter-server/

# 3. 启动（建议用 systemd 守护，见下）
cd /opt/kinter-server
PORT=8787 DATA_DIR=/opt/kinter-server/data PUBLIC_URL=https://你的域名 node server.js
```

### systemd 守护（开机自启 + 崩溃重启）

`/etc/systemd/system/kinter.service`：

```ini
[Unit]
Description=Kinter Account & Store Server
After=network.target

[Service]
WorkingDirectory=/opt/kinter-server
ExecStart=/usr/bin/node server.js
Environment=PORT=8787
Environment=DATA_DIR=/opt/kinter-server/data
Environment=PUBLIC_URL=https://你的域名
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now kinter
curl http://localhost:8787/healthz   # 应返回 ok
```

## 三、HTTPS（必做）

用 Caddy 最省事（自动签发证书）：

```
# /etc/caddy/Caddyfile
你的域名 {
    reverse_proxy localhost:8787
}
```

或 Nginx + certbot：

```
server {
    listen 443 ssl;
    server_name 你的域名;
    ssl_certificate     /etc/letsencrypt/live/你的域名/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/你的域名/privkey.pem;
    location / {
        proxy_pass http://localhost:8787;
        proxy_set_header Host $host;
    }
}
```

## 四、App 端配置

- App 内 **设置 → 服务器** 填入 `https://你的域名`（或 AppSettings.authServerURL）
- 之后注册/登录/发布/购买/下载全部走这个地址

## 五、安全说明

- 付费应用 ZIP 下载已鉴权：**未登录 401 / 未购买 403 / 通过则下发**
- 发布者本人可下载自己的付费应用（测试用）
- 购买记录服务端持久化，换机/重装后登录即可恢复
- 生产环境建议把 `DATA_DIR` 指到独立磁盘并**定期备份 db.json 与 apps/ 目录**

## 六、验证清单

```bash
# 健康检查
curl https://你的域名/healthz                      # ok

# 未登录下载付费应用 → 401
curl -i https://你的域名/store/alice/apps/paidapp/1.0.0.zip

# 注册+登录
curl -X POST https://你的域名/api/register -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"pass1234","name":"Alice"}'

# 购买 → 已购列表
curl -X POST https://你的域名/api/apps/purchase -H "Authorization: Bearer <token>" \
  -H 'Content-Type: application/json' -d '{"appId":"paidapp"}'
curl https://你的域名/api/apps/owned -H "Authorization: Bearer <token>"

# 带 token 下载付费应用 → 200
curl -i https://你的域名/store/alice/apps/paidapp/1.0.0.zip -H "Authorization: Bearer <token>"
```
