#!/bin/bash
#
# JRunner 构建入口 —— 本地 build.sh 和 CI 的 Release workflow 都走这里,
# 保证「本机跑出来的」和「Release 里下到的」是同一个产物。
#
# 用法:
#   scripts/build_app.sh                 # 原生架构,输出到仓库根目录/JRunner.app
#   UNIVERSAL=1 scripts/build_app.sh     # 通用二进制(arm64 + x86_64)
#   OUT_DIR=dist scripts/build_app.sh    # 指定输出目录
#
# 可覆盖的环境变量:
#   OUT_DIR            输出目录(默认仓库根目录)
#   UNIVERSAL          1 = 构建 arm64+x86_64 通用包
#   BUILD_NUMBER       覆盖 CFBundleVersion(默认 git 提交数,CI 上为 run number)
#   CODESIGN_IDENTITY  签名身份(默认 "-" 即 ad-hoc 签名)
#   SKIP_ICON          1 = 跳过图标生成(图标源缺失时自动跳过)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="JRunner"
OUT_DIR="${OUT_DIR:-$ROOT}"
UNIVERSAL="${UNIVERSAL:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APP="$OUT_DIR/$APP_NAME.app"

say() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 版本号 ----------

[ -f VERSION ] || die "找不到 VERSION 文件"
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] \
  || die "VERSION 内容不合法: '$VERSION'(应形如 1.0.0)"

if [ -n "${BUILD_NUMBER:-}" ]; then
  BUILD="$BUILD_NUMBER"
elif BUILD="$(git rev-list --count HEAD 2>/dev/null)"; then
  :
else
  BUILD="1"
fi

YEAR="$(date +%Y)"

# ---------- 编译 ----------

ARCH_FLAGS=()
ARCH_LABEL="native"
if [ "$UNIVERSAL" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  ARCH_LABEL="universal (arm64 + x86_64)"
fi

# macOS 自带 bash 3.2 在 set -u 下展开空数组会报 unbound variable,
# 必须写成 ${arr[@]+"${arr[@]}"} 这种兼容形式
say "版本 v$VERSION (build $BUILD) · $ARCH_LABEL"
say "编译 release"

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --disable-sandbox

BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
[ -x "$BIN_DIR/$APP_NAME" ] || die "编译产物不存在: $BIN_DIR/$APP_NAME"

# ---------- 组装 bundle ----------

say "组装 $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Info.plist:从模板替换占位符(版本号只认 VERSION 文件,不手改 plist)
[ -f Packaging/Info.plist ] || die "找不到 Packaging/Info.plist"
sed -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD|g" \
    -e "s|__YEAR__|$YEAR|g" \
    Packaging/Info.plist > "$APP/Contents/Info.plist"

plutil -lint "$APP/Contents/Info.plist" >/dev/null \
  || die "生成的 Info.plist 不合法"

# 图标:1024 源图 → iconset → icns
if [ "${SKIP_ICON:-0}" != "1" ]; then
  [ -f icon_1024.png ] || die "缺少 icon_1024.png,先跑 swift scripts/make_icon.swift 生成"
  say "生成图标"
  WORK="$(mktemp -d)"
  ICONSET="$WORK/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
    d=$((s * 2))
    sips -z "$d" "$d" icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$WORK"
else
  say "跳过图标(SKIP_ICON=1)"
fi

# ---------- 签名 ----------

say "签名 ($CODESIGN_IDENTITY)"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP" 2>/dev/null \
  || die "codesign 失败"

codesign --verify --deep --strict "$APP" 2>/dev/null \
  || say "警告:codesign 校验未通过(ad-hoc 签名可忽略)"

# ---------- 结果 ----------

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || echo '?')"

say "完成: $APP"
say "  CFBundleShortVersionString = $BUILT_VERSION"
say "  架构 = $ARCHS · 体积 = $(du -sh "$APP" | cut -f1)"
