#!/bin/bash
# 构建未签名 IPA（供极客用户自签分发）
# 用法: ./build_unsigned_ipa.sh [Debug|Release]
set -euo pipefail

CONFIG="${1:-Release}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/Kinter.xcarchive"
PAYLOAD="$BUILD_DIR/Payload"
OUT_IPA="$BUILD_DIR/Kinter-unsigned.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ 未找到 xcodebuild，请安装 Xcode" >&2
  exit 1
fi

PROJ=$(find "$PROJECT_DIR" -maxdepth 2 -name '*.xcodeproj' | head -1)
if [ -z "$PROJ" ]; then
  echo "❌ 未找到 .xcodeproj，请先在 Xcode 中创建工程" >&2
  exit 1
fi

echo "📦 构建 $CONFIG ..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJ" \
  -scheme "Kinter" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

echo "📂 打包 Payload ..."
APP=$(find "$ARCHIVE/Products" -maxdepth 3 -name '*.app' | head -1)
if [ -z "$APP" ]; then
  echo "❌ archive 中未找到 .app" >&2
  exit 1
fi

mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"

pushd "$BUILD_DIR" >/dev/null
zip -qry "$OUT_IPA" Payload
popd >/dev/null

rm -rf "$PAYLOAD"

SIZE=$(du -h "$OUT_IPA" | awk '{print $1}')
echo "✅ 完成: $OUT_IPA ($SIZE)"
echo ""
echo "分发方式："
echo "  - AltStore / SideStore / Sideloadly 自签安装"
echo "  - TrollStore 直接安装（设备版本需在支持区间）"
echo "  - 安装后需在 设置→隐私与安全性→开发者模式 中开启"
