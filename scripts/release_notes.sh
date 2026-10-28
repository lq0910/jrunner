#!/bin/bash
#
# 生成本次发布的 Release Notes 到 stdout。
# 本地 scripts/release.sh 和 CI 共用,保证两边文案一致。
#
# 用法: scripts/release_notes.sh <version>
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"

# 上一个标签(排除当前 HEAD 上的标签)
PREV="$(git describe --tags --abbrev=0 --match 'v*' HEAD 2>/dev/null || true)"
if [ -n "$PREV" ] && [ "$(git rev-list -n1 "$PREV")" = "$(git rev-list -n1 HEAD)" ]; then
  PREV="$(git describe --tags --abbrev=0 --match 'v*' "$PREV^" 2>/dev/null || true)"
fi

if [ -n "$PREV" ]; then
  RANGE="$PREV..HEAD"
  RANGE_LABEL="$PREV → HEAD"
else
  RANGE="HEAD"
  RANGE_LABEL="首个版本"
fi

# 按前缀归类,顺手把纯 CI / 合并提交过滤掉
collect() {
  git log "$RANGE" --no-merges --pretty=format:'%s' 2>/dev/null \
    | grep -Ei "$1" | sed -E 's/^[a-z]+(\([^)]*\))?: *//' | head -40 || true
}

FEATS="$(collect '^(feat|feature|新增|支持)')"
FIXES="$(collect '^(fix|bugfix|修复)')"
PERFS="$(collect '^(perf|refactor|优化|重构)')"
OTHERS="$(git log "$RANGE" --no-merges --pretty=format:'%s' 2>/dev/null \
  | grep -Eiv '^(feat|feature|fix|bugfix|perf|refactor|docs|chore|ci|test|style|build|新增|支持|修复|优化|重构)' \
  | head -20 || true)"

section() {
  [ -n "$2" ] || return 0
  printf '### %s\n' "$1"
  printf '%s\n' "$2" | sed 's/^/- /'
  printf '\n'
}

cat <<EOF
JRunner **v$VERSION**

轻量级 Java / Kotlin 服务启动器 —— 不开 IDE 也能一键起服务、一键打镜像、看实时日志。

### 安装

1. 下载 \`JRunner-$VERSION.zip\`(或 \`JRunner-$VERSION.dmg\`)并解压 / 挂载
2. 把 \`JRunner.app\` 拖到「应用程序」
3. 首次打开若提示「无法验证开发者」,右键 → 打开,或执行:
   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/JRunner.app
   \`\`\`

> 构建产物为 ad-hoc 签名(未做 Apple 公证),不影响本地运行。

### 变更($RANGE_LABEL)

EOF

section "新功能" "$FEATS"
section "修复" "$FIXES"
section "优化与重构" "$PERFS"
section "其他" "$OTHERS"

cat <<EOF
### 校验

\`\`\`bash
shasum -a 256 -c JRunner-$VERSION.sha256
\`\`\`

EOF

if [ -n "$PREV" ]; then
  echo "**完整变更**: https://github.com/lq0910/jrunner/compare/$PREV...v$VERSION"
else
  echo "**完整变更**: https://github.com/lq0910/jrunner/releases/tag/v$VERSION"
fi
