#!/bin/bash
# 配置 Git alias
# 用法: source .scripts/git-helpers/setup-git-alias.sh

# 获取项目根目录
REPO_ROOT="$(git rev-parse --show-toplevel)"

# 配置 git alias（使用相对于仓库根目录的路径）
git config alias.sync-upstream "!bash '$REPO_ROOT/.scripts/git-helpers/git-sync-upstream.sh'"
git config alias.create-pr "!bash '$REPO_ROOT/.scripts/git-helpers/git-create-pr.sh'"

echo "✅ Git alias 配置完成"
echo ""
echo "可用命令:"
echo "  git sync-upstream  - 同步上游更新"
echo "  git create-pr      - 创建 Pull Request"
echo ""
echo "查看配置:"
echo "  git config --get-regexp 'alias\.(sync-upstream|create-pr)'"
