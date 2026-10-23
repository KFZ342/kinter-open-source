#!/bin/bash
# 一键生成 Xcode 工程（依赖 XcodeGen）
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR/Tools"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "⚠️  未安装 xcodegen，正在尝试通过 Homebrew 安装..."
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "❌ 请先安装 Homebrew 或手动安装 xcodegen: https://github.com/yonaskolb/XcodeGen"
    exit 1
  fi
fi

xcodegen generate --spec project.yml --project "$DIR"
echo "✅ 已生成 $DIR/MiniAppHost.xcodeproj"
echo "打开工程: open $DIR/MiniAppHost.xcodeproj"
