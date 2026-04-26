#!/bin/bash
# 配置 Git alias
# 用法: source .scripts/git-helpers/setup-git-alias.sh

# 获取脚本目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 配置 git alias
git config alias.sync-upstream "!$SCRIPT_DIR/git-sync-upstream.sh"
git config alias.create-pr "!$SCRIPT_DIR/git-create-pr.sh"

echo "✅ Git alias 配置完成"
echo ""
echo "可用命令:"
echo "  git sync-upstream  - 同步上游更新"
echo "  git create-pr      - 创建 Pull Request"
echo ""
echo "查看配置:"
echo "  git config --get-regexp alias"
