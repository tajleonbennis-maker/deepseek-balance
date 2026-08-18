#!/bin/bash
# 编译并打包 DeepSeekBalance.app（macOS 菜单栏应用）
set -e
cd "$(dirname "$0")"

APP="DeepSeekBalance.app"
echo "==> 清理旧产物"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> swiftc 编译（Swift 5 语言模式，避免 Swift 6 严格并发检查）"
swiftc -O -swift-version 5 \
  -framework AppKit -framework UserNotifications \
  -o "$APP/Contents/MacOS/DeepSeekBalance" \
  Sources/main.swift Sources/AppDelegate.swift Sources/Models.swift \
  Sources/Store.swift Sources/BalanceFetcher.swift \
  Sources/StatusMenuController.swift Sources/SettingsWindowController.swift

echo "==> 拷贝 Info.plist"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> 拷贝图标"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "    (无图标，跳过)"
fi

echo "==> 本地签名（ad-hoc）"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "    (签名跳过)"

echo ""
echo "✅ 构建完成：$(pwd)/$APP"
echo "   运行：open \"$APP\""
