# Fork 工作流指南

本文档说明如何在使用 fork 工作流向 Lingyan000/fluxdo 贡献代码的同时，保持个人开发工具配置。

## 项目概述

- **上游仓库**: Lingyan000/fluxdo
- **你的 Fork**: okamitimo233/fluxdo
- **主要贡献类型**: 核心功能开发、Bug 修复、文档改进

## Git Remote 配置

确保你的本地仓库配置了两个 remote：

```bash
# 查看当前 remote
git remote -v

# 应该看到：
# origin    git@github.com:okamitimo233/fluxdo.git (你的 fork)
# upstream  git@github.com:Lingyan000/fluxdo.git (上游仓库)
```

如果缺少 upstream，添加它：

```bash
git remote add upstream git@github.com:Lingyan000/fluxdo.git
```

## 个人配置文件管理

### 哪些是个人配置文件？

- `AGENTS.md` — Trellis AI 工作流配置
- `CLAUDE.md` — 项目开发规范 + GitNexus 配置

这些文件包含个人 AI 工具配置和频繁变化的统计数据（GitNexus symbol count 等），不应提交到上游。

### 如何忽略本地修改

使用 Git 的 `assume-unchanged` 标记：

```bash
# 忽略这些文件的本地修改
git update-index --assume-unchanged AGENTS.md
git update-index --assume-unchanged CLAUDE.md

# 验证设置
git ls-files -v | grep '^h' | grep -E 'AGENTS.md|CLAUDE.md'
# 应该看到 h 开头的条目
```

### 查看当前状态

```bash
# 检查哪些文件被标记为 assume-unchanged
git ls-files -v | grep '^h'

# 查看这些文件是否还有未提交的修改
git status
```

### 当上游更新这些文件时

如果上游修改了 `CLAUDE.md`（比如更新项目规范），你需要手动同步：

```bash
# 1. 临时取消 assume-unchanged 标记
git update-index --no-assume-unchanged CLAUDE.md

# 2. 查看上游的修改
git fetch upstream
git diff upstream/main CLAUDE.md

# 3. 选择性合并上游的修改（保留你的个人配置）
# 方法 A: 使用 git merge-file
git show upstream/main:CLAUDE.md > /tmp/upstream-claude.md
git merge-file CLAUDE.md /tmp/base-claude.md /tmp/upstream-claude.md

# 方法 B: 手动编辑，复制上游有用的部分

# 4. 重新标记为 assume-unchanged
git update-index --assume-unchanged CLAUDE.md
```

## Fork 工作流

### 快速开始

```bash
# 1. 配置 Git alias（首次使用）
source .scripts/git-helpers/setup-git-alias.sh

# 2. 设置个人配置文件为 assume-unchanged（首次使用）
git update-index --assume-unchanged AGENTS.md CLAUDE.md

# 3. 同步上游更新
git sync-upstream

# 4. 创建功能分支
git checkout -b feature/my-feature

# 5. 开发完成后，创建 PR（会先预览）
git create-pr --dry-run  # 先预览
git create-pr            # 确认后创建
```

### 1. 同步上游更新

**使用 Git Alias（推荐）**：

```bash
git sync-upstream
```

这个命令会自动：
1. Fetch upstream 最新代码
2. Merge 到你的本地 main 分支
3. Push 到你的 origin

**手动执行**：

```bash
# 1. 获取上游最新代码
git fetch upstream

# 2. 切换到 main 分支
git checkout main

# 3. 合并上游更新
git merge upstream/main

# 4. 推送到你的 fork
git push origin main
```

### 2. 创建功能分支

```bash
# 从最新的 main 创建分支
git checkout main
git pull upstream main
git checkout -b feature/your-feature-name

# 或使用简短命名
git checkout -b fix/issue-123
git checkout -b docs/update-readme
```

分支命名约定：
- `feature/` — 新功能
- `fix/` — Bug 修复
- `docs/` — 文档改进
- `refactor/` — 代码重构

### 3. 提交代码

```bash
# 正常的提交流程
git add <files>
git commit -m "清晰的提交信息"

# 推送到你的 fork
git push origin feature/your-feature-name
```

**提交前检查清单**：
- [ ] 已运行测试（如果有）
- [ ] 已更新相关文档
- [ ] 提交信息清晰描述改动
- [ ] 确保没有提交 AGENTS.md 或 CLAUDE.md 的修改

检查是否误提交了个人配置：

```bash
# 查看即将推送的提交中是否包含这些文件
git log origin/main..HEAD --name-only --oneline | grep -E 'AGENTS.md|CLAUDE.md'

# 如果包含，从提交中移除
git reset HEAD~1 AGENTS.md CLAUDE.md
git commit --amend
```

### 4. 创建 Pull Request

**使用 Git Alias（推荐）**：

```bash
# 预览将要创建的 PR（dry-run 模式）
git create-pr --dry-run

# 确认无误后，实际创建 PR
git create-pr
```

**注意**: `git create-pr` 命令会先展示即将执行的操作，等待你确认后才创建 PR。

**手动创建**：

1. 访问你的 fork: https://github.com/okamitimo233/fluxdo
2. GitHub 会提示 "Compare & pull request"
3. 确认 base repository 是 `Lingyan000/fluxdo` 的 `main` 分支
4. 填写 PR 标题和描述：
   - 说明改动的目的
   - 关联相关的 Issue
   - 列出测试步骤（如果适用）
5. 点击 "Create pull request"

## 处理常见问题

### 问题 1: AGENTS.md 或 CLAUDE.md 出现在 git status 中

```bash
# 检查是否被标记为 assume-unchanged
git ls-files -v | grep -E 'AGENTS.md|CLAUDE.md'

# 如果没有 h 前缀，重新标记
git update-index --assume-unchanged AGENTS.md
git update-index --assume-unchanged CLAUDE.md
```

### 问题 2: 合并上游时出现冲突

```bash
# 查看冲突文件
git status

# 对于个人配置文件（AGENTS.md/CLAUDE.md）
# 直接使用本地版本（保留你的配置）
git checkout --ours AGENTS.md CLAUDE.md
git add AGENTS.md CLAUDE.md

# 对于核心代码文件
# 手动解决冲突后
git add <resolved-files>
git commit
```

### 问题 3: 不小心提交了个人配置文件

```bash
# 如果还没有 push
git reset HEAD~1

# 重新提交，排除这些文件
git add <其他文件>
git commit -m "你的提交信息"

# 如果已经 push 到 origin
git revert <commit-hash>
git push origin <branch-name>
```

### 问题 4: 上游 force push 或历史重写

```bash
# 警告：这会重置你的本地 main 分支
git fetch upstream
git checkout main
git reset --hard upstream/main
git push origin main --force

# 你的功能分支不受影响，可以继续开发
```

## Git Alias 配置

本项目提供了便捷的 Git alias，位于 `.scripts/git-helpers/` 目录。

### 快速设置

首次使用前，配置 Git alias：

```bash
# 在项目根目录执行
source .scripts/git-helpers/setup-git-alias.sh
```

这会配置以下 alias：
- `git sync-upstream` — 同步上游更新
- `git create-pr` — 创建 Pull Request

### 验证配置

```bash
git config --get-regexp 'alias\.(sync-upstream|create-pr)'
```

### 可用命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `git sync-upstream` | 同步上游更新到本地 main | `git sync-upstream` |
| `git create-pr` | 创建 Pull Request（带确认） | `git create-pr --dry-run` |

## 最佳实践

### 提交前

1. **同步上游**: 确保 main 分支是最新的
   ```bash
   git sync-upstream
   ```

2. **检查修改**: 确认只包含预期的文件
   ```bash
   git status
   git diff
   ```

3. **本地测试**: 运行测试和代码检查
   ```bash
   flutter test
   flutter analyze
   ```

### 提交信息规范

使用清晰、描述性的提交信息：

```
feat: 添加用户登录功能

- 实现 OAuth2.0 认证流程
- 添加登录状态持久化
- 更新相关测试用例

Closes #123
```

格式：
- `feat:` — 新功能
- `fix:` — Bug 修复
- `docs:` — 文档改进
- `refactor:` — 代码重构
- `test:` — 测试相关
- `chore:` — 构建/工具相关

### PR 审核反馈

当收到审核意见后：

```bash
# 在功能分支上继续修改
git checkout feature/your-feature-name

# 添加新的提交
git add <files>
git commit -m "根据审核意见修改 XXX"
git push origin feature/your-feature-name

# PR 会自动更新
```

## 参考资源

- [GitHub Fork 工作流文档](https://docs.github.com/en/get-started/quickstart/fork-a-repo)
- [Git assume-unchanged 文档](https://git-scm.com/docs/git-update-index#_using_assume_unchanged_bit)
- 项目 Trellis 工作流: `.trellis/workflow.md`
