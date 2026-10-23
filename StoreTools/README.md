# Kinter Store

Kinter 小程序商店源。

## 这是什么

这是一个**静态源**，不需要服务器。客户端通过拉取 `index.json` 获取应用列表，从 `apps/` 目录下载 ZIP。

## 使用

在 Kinter App 的「商店」页，点右上角图标，添加源：

```
https://cdn.jsdelivr.net/gh/USER/kinter-store@main/index.json
```

## 目录结构

```
apps/
  <应用名>/
    manifest.json     ← 应用元数据
    icon.png          ← 图标（可选）
    1.0.0.zip         ← 版本包
index.json            ← 自动生成，勿手改
build_index.py        ← 生成脚本
```

## 发布新应用

1. 在 `apps/` 下新建目录，放入 `manifest.json`、`icon.png`、ZIP
2. 运行 `python3 build_index.py`
3. commit 并 push

## 发布新版本

1. 把新 ZIP 命名为新版本号（如 `1.0.1.zip`）放进应用目录
2. 更新 `manifest.json` 里的 `version`
3. 运行 `python3 build_index.py`
4. commit 并 push

客户端会在下次刷新时看到更新。

## 创建自己的源

Fork 这个仓库，改 `build_index.py` 里的默认 base URL 为你的用户名，推送即可。
