#!/bin/bash
#
# 版本号自增工具。改的是根目录 VERSION 文件 —— 它是唯一的版本来源。
#
# 用法:
#   scripts/bump-version.sh patch     # 1.0.0 → 1.0.1
#   scripts/bump-version.sh minor     # 1.0.1 → 1.1.0
#   scripts/bump-version.sh major     # 1.1.0 → 2.0.0
#   scripts/bump-version.sh 1.4.2     # 直接指定
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

[ -f VERSION ] || { echo "找不到 VERSION 文件" >&2; exit 1; }

CUR="$(tr -d '[:space:]' < VERSION)"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CUR"

case "${1:-}" in
  patch) NEW="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) NEW="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEW="$((MAJOR + 1)).0.0" ;;
  "")
    echo "当前版本: $CUR"
    echo "用法: scripts/bump-version.sh patch|minor|major|<x.y.z>"
    exit 0 ;;
  *)
    NEW="$1" ;;
esac

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] \
  || { echo "版本号不合法: $NEW" >&2; exit 1; }

printf '%s\n' "$NEW" > VERSION
echo "版本: $CUR → $NEW"
echo
echo "下一步:"
echo "    git add VERSION && git commit -m \"chore: 发布 v$NEW\""
echo "    git push origin HEAD"
echo "    # Actions 检测到 VERSION 变更后自动打 v$NEW 标签并发布 Release"
