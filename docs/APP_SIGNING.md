# 给小程序签名

Kinter 会把每个导入的包当成「别人做的软件」看待：打开之前先验一次签名。没签名、或者签名和包里的文件对不上，就弹一句 iOS 用户都见过的提示——**未受验证的开发者，App暂时无法打开**——然后不启动。

## 为什么不是装的时候看一眼就完了

安装弹窗展示的是「这个包**当时**想要哪些能力」，它不能回答「这个包**现在**还是不是当初那个人给的那个包」。小程序跑在本地，装完之后文件被替换、被塞了一段脚本，肉眼看不出来。所以签名不在安装时一次性放行，而是**每次点开都重新计算**整包摘要、重新验一次。

## 包里多了什么

应用根目录多一个 `signature.json`：

```json
{
  "algorithm": "ed25519",
  "developerId": "com.example.dev",
  "publicKey": "3eNlQ2pCx7zih55/eJ/6mxrvTQW0Wapt3EmdACJBwhc=",
  "signature": "N6dK4JaUlTgc3fzD...",
  "signedAt": "2026-11-07T12:37:13Z",
  "review": "{\"kind\":\"kinter-model-review\",\"model\":\"gpt-4o-mini\",\"verdict\":\"safe\",…}",
  "reviewSignature": "…对 review 原文 SHA256 的签名…"
}
```

`publicKey` 是 32 字节 raw Ed25519 公钥的 base64。宿主用一把内置的公钥？没有——公钥跟着签名走，第一次遇到会问你要不要信这个开发者。**信任的是「这把钥匙 + 这个开发者标识」，不是「这个包」**，所以同一个开发者后面发的包不再问。

## 签名之前先送审

签名不是「开发者自己说没问题」就发证书。`Tools/sign_app.py` 会先把 manifest 和包里的文本源码（HTML / JS / CSS / KTML / JSON 等，单文件 60 KB、总共 220 KB 封顶）发给第三方模型，让它按一份固定标准判一次：

- 偷通讯录 / 相册 / 剪贴板 / 定位 / 健康数据往外传
- 编码或加密后外发、先读隐私再联网
- `eval`、动态加载远程脚本
- 伪装系统界面骗权限
- 挖矿、刷量、绕过安全模式、读别的小程序数据

判为 `unsafe`（或 `risk=high`）时，工具**直接退出，不写签名、不发证书**，并把风险点逐条打出来。只有 `verdict=safe` 才会进入签名步骤。

接口是 OpenAI 兼容的 `/chat/completions`，地址、Key、模型名三个参数第一次填写后存在 `~/.kinter/sign_config.json`（权限 600），也可以每次用参数覆盖：

```bash
python3 Tools/sign_app.py ./my-app \
  --developer com.example.dev \
  --api-base https://api.example.com/v1 \
  --api-key sk-xxx \
  --model gpt-4o-mini
```

没配接口时工具会交互式问你要，不会跳过审查。

审查结论本身也进签名：`review` 字段保存模型名、结论、风险点、包摘要原文，`reviewSignature` 是对这段原文 SHA256 的 Ed25519 签名。宿主验签时两样一起验——审查记录被改过，同样打不开。

## 签什么

不是 `manifest.json` 一个文件，而是目录里所有普通文件的清单摘要：

```text
按 UTF-8 字节排序的相对路径
  每个文件 → SHA256(内容) → hex
拼成 path\0hash\n
再整体 SHA256
→ Ed25519 对这个 32 字节摘要签名
```

`signature.json` 自己不参与摘要，否则签完就自相矛盾。这套规则在 `PackageSignature.digest`（`HostApp/Core/Package/PackageInspector.swift`）和 `Tools/sign_app.py` 里各实现一遍，两边必须逐字节一致。

## 怎么签

```bash
# 第一次会生成 dev_ed25519.pem（私钥，自己收好）和 .pub
python3 Tools/sign_app.py ./my-app --developer com.example.dev

# 用自己的密钥
python3 Tools/sign_app.py ./my-app --developer com.example.dev --key ~/keys/dev_ed25519.pem
```

签完再打包 ZIP：

```bash
cd my-app && zip -r ../my-app.zip .
```

导入后第一次打开会问：「签名有效，但开发者还没被这台设备信任。」点**信任并打开**就进；点取消就留在外面。

## 什么时候会被挡

| 情况 | 弹窗 |
|---|---|
| 没有 `signature.json` | 未受验证的开发者，App暂时无法打开 |
| 签名有，但对不上（文件被改过 / 公钥无效 / 格式不对） | 同上，并在正文里说明「签名与本机文件不匹配」 |
| 签名有效，开发者没被信任 | 同标题，副文案说明开发者标识和模型审查结论，给「信任并打开」 |
| 签名有效，开发者已信任 | 直接进 |
| 审查记录被改过 | 同「签名对不上」，提示安全审查记录被改动 |
| 宿主自带示例、本机 AI 生成 | 直接进（本机产物，不算外部开发者） |

「本机产物」这个豁免是写进 `InstalledApp.isFirstParty` 的，安装时落库，跟着 library.json 一起存。

## 关掉它

设置 → 开发者签名 → 关掉「要求开发者签名」。关掉后所有包直接开，不做任何验签；再打开时，没签名的包又会开始被挡。

设置里还能看到信任了几位开发者，一键清空；清空后旧包会重新问一遍。

## 边界

- 签名证明的是**完整性**（包没被换过），不是**身份可信**。谁做的、该不该信，仍然是你点「信任并打开」那一下决定的。
- 私钥泄露等于身份被冒用。`dev_ed25519.pem` 不要进仓库、不要发给别人。
- 模型审查是**辅助判断**，不是保证。它看的是文本源码，看不了图片里藏的指令，也拦不住精心伪装的逻辑；真正的兜底还是宿主的能力网关和安全模式。
- 本版本不校验证书链、没有开发者账号体系；如果以后要做商店审核，这一层可以换成「平台签发证书 + 撤销列表」。
