#!/bin/bash
# 同步上游仓库更新到本地 main 分支
# 用法: git sync-upstream

set -e

echo "🔄 开始同步上游仓库..."

# 保存当前分支
CURRENT_BRANCH=$(git branch --show-current)

# 切换到 main 分支
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "📍 切换到 main 分支..."
    git checkout main
fi

# Fetch upstream
echo "⬇️  获取上游最新代码..."
git fetch upstream

# 检查是否有更新
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse upstream/main)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "✅ 本地已是最新版本"
    if [ "$CURRENT_BRANCH" != "main" ]; then
        echo "📍 切换回 $CURRENT_BRANCH 分支..."
        git checkout "$CURRENT_BRANCH"
    fi
    exit 0
fi

# 显示即将合并的提交
echo ""
echo "📋 上游更新内容:"
git log HEAD..upstream/main --oneline --decorate
echo ""

# Merge upstream/main
echo "🔀 合并 upstream/main..."
git merge upstream/main

# Push to origin
echo "⬆️  推送到 origin..."
git push origin main

echo ""
echo "✅ 同步完成！"

# 切换回原分支
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "📍 切换回 $CURRENT_BRANCH 分支..."
    git checkout "$CURRENT_BRANCH"
fi
