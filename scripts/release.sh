#!/bin/bash
#
# 打一个可发布的 JRunner 版本:编译 → 组包 → zip/dmg → 校验和 → (可选)发 Release。
#
# 用法:
#   scripts/release.sh                  # 只在本地生成 dist/ 里的产物,不动远端
#   scripts/release.sh --tag            # 额外创建本地 git 标签 v<version>
#   scripts/release.sh --publish        # 创建标签 + 推送 + gh 发 Release(需 gh 已登录)
#
# 选项:
#   --native     只编本机架构(默认通用二进制 arm64 + x86_64)
#   --no-dmg     不生成 dmg
#   --no-zip     不生成 zip
#   -y, --yes    跳过确认
#
# 发布版本的常规姿势:改 VERSION → 提交 → 推 main,GitHub Actions 会自动
# 打标签、构建并发布 Release(见 .github/workflows/release.yml)。
# 这个脚本是「本地一把梭」和「CI 挂了要手动补发」时的兜底。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO_SLUG="lq0910/jrunner"
UNIVERSAL=1
MAKE_DMG=1
MAKE_ZIP=1
DO_TAG=0
DO_PUBLISH=0
ASSUME_YES=0

say() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --native)   UNIVERSAL=0 ;;
    --no-dmg)   MAKE_DMG=0 ;;
    --no-zip)   MAKE_ZIP=0 ;;
    --tag)      DO_TAG=1 ;;
    --publish)  DO_TAG=1; DO_PUBLISH=1 ;;
    -y|--yes)   ASSUME_YES=1 ;;
    -h|--help)  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "未知参数: $1(用 --help 查看用法)" ;;
  esac
  shift
done

# ---------- 前置检查 ----------

[ -f VERSION ] || die "找不到 VERSION 文件"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then
  say "工作区有未提交改动,这些改动不会进入 tag:"
  git status --short
  if [ "$ASSUME_YES" != "1" ]; then
    read -r -p "继续?[y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
  fi
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "标签 $TAG 已存在。要重发请先:git tag -d $TAG && git push origin :refs/tags/$TAG"
fi

if [ "$DO_PUBLISH" = "1" ]; then
  command -v gh >/dev/null || die "未安装 gh(GitHub CLI):brew install gh"
  gh auth status >/dev/null 2>&1 || die "gh 未登录:gh auth login"
fi

# ---------- 构建 ----------

DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

UNIVERSAL="$UNIVERSAL" OUT_DIR="$DIST" "$ROOT/scripts/build_app.sh"

APP="$DIST/JRunner.app"
[ -d "$APP" ] || die "构建产物缺失: $APP"

# ---------- 打包 ----------

ZIP="$DIST/JRunner-$VERSION.zip"
DMG="$DIST/JRunner-$VERSION.dmg"

if [ "$MAKE_ZIP" = "1" ]; then
  say "生成 zip"
  # ditto 保留符号链接 / 资源分支 / 权限,比 zip -r 靠谱
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
fi

if [ "$MAKE_DMG" = "1" ]; then
  say "生成 dmg"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "JRunner $VERSION" \
    -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  rm -rf "$STAGE"
fi

say "生成 Release Notes"
NOTES="$DIST/RELEASE_NOTES.md"
"$ROOT/scripts/release_notes.sh" "$VERSION" > "$NOTES"

say "生成校验和"
(
  cd "$DIST"
  FILES=()
  [ -f "$(basename "$ZIP")" ] && FILES+=("$(basename "$ZIP")")
  [ -f "$(basename "$DMG")" ] && FILES+=("$(basename "$DMG")")
  shasum -a 256 "${FILES[@]}" > "JRunner-$VERSION.sha256"
)

# 只保留要发布的东西,别把 .app 目录也留在 dist 里
rm -rf "$APP"

echo
say "产物清单 ($DIST)"
ls -lh "$DIST" | tail -n +2 | awk '{printf "    %-34s %s\n", $9, $5}'
echo

# ---------- 发布 ----------

if [ "$DO_TAG" = "1" ]; then
  say "创建标签 $TAG"
  git tag -a "$TAG" -m "JRunner $TAG"

  if [ "$DO_PUBLISH" = "1" ]; then
    say "推送标签与提交"
    git push origin HEAD
    git push origin "refs/tags/$TAG"

    say "创建 GitHub Release"
    ASSETS=()
    [ -f "$ZIP" ] && ASSETS+=("$ZIP")
    [ -f "$DMG" ] && ASSETS+=("$DMG")
    ASSETS+=("$DIST/JRunner-$VERSION.sha256")

    gh release create "$TAG" "${ASSETS[@]}" \
      --repo "$REPO_SLUG" \
      --title "JRunner $TAG" \
      --notes-file "$NOTES" \
      --verify-tag

    say "已发布: https://github.com/$REPO_SLUG/releases/tag/$TAG"
  else
    say "本地标签已创建,推送命令:"
    echo "    git push origin HEAD && git push origin refs/tags/$TAG"
  fi
else
  say "未创建标签。下一步:"
  echo "    git push origin HEAD                  # 只推代码"
  echo "    # Actions 会在 VERSION 变更时自动打标签并发布 Release"
  echo "    # 或本地补发: scripts/release.sh --publish"
fi
