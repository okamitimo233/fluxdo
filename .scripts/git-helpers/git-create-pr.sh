#!/bin/bash
# 创建 Pull Request 到上游仓库
# 用法: git create-pr [--dry-run]

set -e

# 检查是否在 git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ 错误: 当前目录不是 git 仓库"
    exit 1
fi

# 检查 upstream remote 是否存在
if ! git remote | grep -q "^upstream$"; then
    echo "❌ 错误: 未找到 upstream remote"
    echo "请先添加 upstream: git remote add upstream <url>"
    exit 1
fi

# 获取当前分支
CURRENT_BRANCH=$(git branch --show-current)

if [ -z "$CURRENT_BRANCH" ]; then
    echo "❌ 错误: 无法确定当前分支"
    exit 1
fi

if [ "$CURRENT_BRANCH" = "main" ]; then
    echo "❌ 错误: 不能从 main 分支创建 PR"
    echo "请先创建并切换到功能分支: git checkout -b <branch-name>"
    exit 1
fi

# 检查是否有未提交的修改
if ! git diff-index --quiet HEAD --; then
    echo "⚠️  警告: 存在未提交的修改"
    git status --short
    echo ""
    read -p "是否继续? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ 已取消"
        exit 1
    fi
fi

# 检查是否已 push 到 origin
ORIGIN_BRANCH="origin/$CURRENT_BRANCH"
if ! git rev-parse --verify "$ORIGIN_BRANCH" > /dev/null 2>&1; then
    echo "⚠️  当前分支尚未推送到 origin"
    read -p "是否现在推送? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "⬆️  推送分支到 origin..."
        git push -u origin "$CURRENT_BRANCH"
    else
        echo "❌ 已取消"
        exit 1
    fi
fi

# Dry run 模式
DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
fi

# 获取 upstream 信息
UPSTREAM_REPO=$(git remote get-url upstream | sed -E 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')

# 获取本地 main 和当前分支的差异
echo ""
echo "📋 PR 预览"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "目标仓库: $UPSTREAM_REPO"
echo "目标分支: main"
echo "源分支: $CURRENT_BRANCH"
echo ""
echo "提交内容:"
git log origin/main..HEAD --oneline --decorate
echo ""
echo "修改的文件:"
git diff origin/main...HEAD --stat
echo ""

# 检查是否包含个人配置文件
PERSONAL_FILES=$(git diff origin/main..HEAD --name-only | grep -E '^(AGENTS\.md|CLAUDE\.md)$' || true)
if [ -n "$PERSONAL_FILES" ]; then
    echo "⚠️  警告: PR 中包含个人配置文件:"
    echo "$PERSONAL_FILES"
    echo ""
    echo "建议从 PR 中移除这些文件:"
    echo "  git reset HEAD~1 AGENTS.md CLAUDE.md"
    echo "  git commit --amend"
    echo "  git push origin $CURRENT_BRANCH --force"
    echo ""
fi

if [ "$DRY_RUN" = true ]; then
    echo "🔍 Dry-run 模式 - 不会实际创建 PR"
    echo ""
    echo "PR 创建命令:"
    echo "  gh pr create --repo Lingyan000/fluxdo --base main --head okamitimo233:$CURRENT_BRANCH"
    echo ""
    echo "或访问: $UPSTREAM_REPO/compare/main...okamitimo233:$CURRENT_BRANCH"
    exit 0
fi

# 确认创建 PR
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "确认创建 Pull Request? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 已取消"
    exit 1
fi

# 检查 gh CLI 是否可用
if ! command -v gh &> /dev/null; then
    echo "⚠️  未找到 gh CLI，请手动创建 PR"
    echo ""
    echo "访问: $UPSTREAM_REPO/compare/main...okamitimo233:$CURRENT_BRANCH"
    exit 0
fi

# 获取 PR 标题（从最后一次提交）
PR_TITLE=$(git log -1 --pretty=%B | head -n1)

echo ""
echo "📝 PR 标题: $PR_TITLE"
echo ""
read -p "使用此标题? (Y/n/custom) " -n 1 -r
echo

if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -p "输入新标题: " PR_TITLE
elif [[ $REPLY =~ ^[Cc]$ ]]; then
    read -p "输入新标题: " PR_TITLE
fi

# 创建 PR
echo ""
echo "🚀 创建 Pull Request..."
gh pr create \
    --repo Lingyan000/fluxdo \
    --base main \
    --head "okamitimo233:$CURRENT_BRANCH" \
    --title "$PR_TITLE" \
    --body "## 改动说明

请在此描述你的改动内容。

## 测试步骤

- [ ] 测试步骤 1
- [ ] 测试步骤 2

## 相关 Issue

关联 Issue: #"

echo ""
echo "✅ PR 创建成功！"
