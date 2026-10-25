#!/bin/bash
# TestFlight 构建脚本：Archive + 导出 App Store Connect 分发包
#
# 前置条件（一次性）：
#   1. 已注册 Apple Developer 账号（$99/年）
#   2. 已登录 Xcode（Account 里加入该 Apple ID）
#   3. 已在开发者后台添加 App ID com.kinter.host + HealthKit/NFC capability
#   4. 首次使用时在 Xcode 打开工程，选中 Kinter target → Signing & Capabilities
#      → 勾选 Automatically manage signing → 选择你的 Team
#      （选择后 Team ID 会被写入工程，之后命令行构建无需再手动配置）
#
# 用法：
#   ./Tools/build_testflight.sh
#   或指定导出目录：./Tools/build_testflight.sh /tmp/kinter-tf
set -euo pipefail

cd "$(dirname "$0")/.."

EXPORT_DIR="${1:-/tmp/kinter-testflight}"
ARCHIVE_PATH="$EXPORT_DIR/Kinter.xcarchive"
EXPORT_PLIST="$EXPORT_DIR/export.plist"

echo "==> 1/3 Archive（Release 签名，需要开发者账号）"
xcodebuild -project Kinter.xcodeproj \
  -scheme Kinter \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=iOS' \
  archive

# App Store Connect 分发选项（TestFlight 构建使用）
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>uploadBitcode</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
    <key>teamID</key>
    <string>$(defaults read com.apple.dt.Xcode IDEProvisioningTeamID 2>/dev/null || echo "")</string>
</dict>
</plist>
PLIST

echo "==> 2/3 导出 IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_DIR"

echo "==> 3/3 完成"
echo "IPA 位置: $EXPORT_DIR"
echo "下一步：打开 Xcode → Window → Organizer（或使用以下命令上传）"
echo "   xcrun altool --upload-app -f $EXPORT_DIR/Kinter.ipa -t ios -u 你的AppleID -p 专用密码"
echo "或在 Xcode Organizer 里选中 Archive → Distribute App → App Store Connect → Upload"
