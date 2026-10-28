#!/bin/bash
# 构建 JRunner.app(无 Xcode 工程,纯 SwiftPM + 手工组装 bundle)
set -euo pipefail
cd "$(dirname "$0")"

APP="JRunner.app"
BIN="$APP/Contents/MacOS/JRunner"

echo "==> 编译 (release)"
swift build -c release --disable-sandbox

echo "==> 组装 bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --disable-sandbox --show-bin-path)/JRunner" "$BIN"

if [ -f icon_1024.png ]; then
  ICONSET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$ICONSET"
  for s in 16 32 64 128 256 512; do
    sips -z $s $s icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
fi

echo "==> 签名 (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "==> 完成: $(pwd)/$APP"
