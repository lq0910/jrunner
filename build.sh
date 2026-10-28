#!/bin/bash
#
# 本地快速构建:./build.sh → 仓库根目录下的 JRunner.app
#
# 真正的构建逻辑在 scripts/build_app.sh —— 本机、scripts/release.sh、
# GitHub Actions 三条路走的是同一份代码,产物一致。
#
# 常用:
#   ./build.sh                      # 原生架构
#   UNIVERSAL=1 ./build.sh          # 通用二进制(arm64 + x86_64)
#   scripts/release.sh              # 打 zip / dmg + 校验和
#
set -euo pipefail
cd "$(dirname "$0")"
exec ./scripts/build_app.sh
