# 建立 fork 工作流规范

## Goal

建立标准的 fork 工作流规范，使项目可以：
1. 向上游仓库 (Lingyan000/fluxdo) 提交 Pull Request
2. 保持个人工作配置（如 Trellis、GitNexus 等 AI 工具配置）
3. 同步上游更新，避免冲突

## What I already know

* 当前 Git 配置：
  - origin: okamitimo233/fluxdo.git (用户 fork)
  - upstream: Lingyan000/fluxdo.git (上游仓库)
* 项目使用 Trellis AI 工作流系统
* 项目已集成 GitNexus MCP 用于代码智能分析
* 存在未提交的修改：AGENTS.md, CLAUDE.md (仅 GitNexus 统计数据更新)

### Git 忽略策略

**主 .gitignore 已忽略：**
- `.claude/`, `.codex/`, `.gemini/`, `.opencode/`, `.windsurf/` - AI 工具配置
- `.agents/` - Agents 配置
- `.gitnexus` - GitNexus 索引文件

**Trellis .gitignore 已忽略：**
- `.developer`, `.current-task` - 开发者本地状态
- `.agents/`, `.agent-log`, `.session-id` - Agent 运行时文件

### AGENTS.md 和 CLAUDE.md 的性质

这两个文件包含：
1. Trellis 指引（调用 AI 工作流）
2. GitNexus 配置块（包含自动更新的统计数据）
3. 项目级别的开发规范

**潜在问题：** GitNexus 统计数据会频繁变化，可能不适合提交到上游

## Decision (ADR-lite)

**Context**: AGENTS.md 和 CLAUDE.md 包含个人 AI 工具配置和 GitNexus 统计数据，频繁变化且仅对当前开发者有意义

**Decision**: 
- AGENTS.md 和 CLAUDE.md 作为个人配置保留
- 通过 git update-index --assume-unchanged 在本地忽略修改
- 不提交到 origin 或 PR 到上游
- 仅在上游 CLAUDE.md 更新时手动同步

**Consequences**:
- ✅ 避免频繁的统计数据提交污染历史
- ✅ 可以自由定制个人工作流
- ✅ 不影响向上游贡献核心代码
- ⚠️ 需要手动管理配置文件的同步（当上游有更新时）
- ⚠️ 团队成员间工具配置不统一（但可接受）

## Open Questions

* ~~你希望向上游贡献什么类型的内容？~~ → 综合贡献（功能、Bug修复、文档）
* ~~是否需要自动化脚本来简化 fork 同步流程？~~ → Git alias + 辅助脚本，但必须向用户确认后再创建 PR

## Requirements (evolving)

### 核心需求

1. **个人配置文件管理**
   - AGENTS.md 和 CLAUDE.md 使用 git assume-unchanged 忽略本地修改
   - 保留文件在工作目录中，但不影响 git status
   - 可以在上游更新时手动同步

2. **Fork 工作流文档**
   - 创建 CONTRIBUTING.md 或类似文档说明 fork 工作流
   - 包含如何同步上游、创建 PR 的步骤
   - 说明个人配置文件的处理方式

3. **Git 操作指南**
   - 同步上游更新的命令流程
   - 创建 PR 的步骤说明
   - 处理冲突的方法（特别是个人配置文件）
   - 支持不同类型的贡献（功能、Bug修复、文档）

4. **工作流支持**
   - Feature branch 工作流（新功能）
   - Hotfix branch 工作流（紧急修复）
   - 快速文档修改流程

5. **自动化工具（Git alias + 辅助脚本）**
   - `git sync-upstream` — 同步上游更新
   - `git create-pr` — PR 创建辅助（**必须向用户确认后才执行**）
   - 脚本路径：`.scripts/git-helpers/` 或类似位置
   - 自动处理个人配置文件的 assume-unchanged 状态

6. **安全约束**
   - **NEVER 直接创建/提交 PR** — 必须先向用户展示即将执行的操作并得到确认
   - 所有脚本提供 `--dry-run` 模式预览
   - 提供回滚/撤销机制

## Acceptance Criteria (evolving)

* [x] AGENTS.md 和 CLAUDE.md 已设置为 git assume-unchanged
* [x] 创建 CONTRIBUTING.md 文档，包含完整的 fork 工作流说明
* [x] 创建 `git sync-upstream` alias/脚本，支持同步上游
* [x] 创建 `git create-pr` alias/脚本，包含 dry-run 模式和用户确认机制
* [x] 文档中明确说明个人配置文件的处理方式
* [x] 提供处理个人配置文件冲突的方法说明
* [x] Spec update assessment completed (不需要更新 .trellis/spec/)

## Definition of Done (team quality bar)

* 文档清晰、可执行
* Git 操作流程经过验证
* 个人配置与核心代码分离清晰

## Out of Scope (explicit)

* Trellis 任务系统与 git 工作流的自动化集成
* 多远程仓库支持
* 冲突自动解决机制
- 网络失败自动重试
- CI/CD 环境适配
- 上游历史重写处理
- PR 审核反馈后的自动化修改流程

## Technical Notes

* 项目路径: E:\fluxdo
* Trellis 工作流目录: .trellis/
* GitNexus 配置文件: CLAUDE.md (GitNexus section)
* Git remote 配置:
  - origin: okamitimo233/fluxdo.git
  - upstream: Lingyan000/fluxdo.git
* 已忽略的 AI 工具配置: .claude/, .codex/, .agents/, .gitnexus

### 实施记录

**Phase 1: 文档和配置** ✅
- [x] 创建 CONTRIBUTING.md 文档（359 行）
- [x] 设置 AGENTS.md 和 CLAUDE.md 为 assume-unchanged
- [x] 验证 git status 不再显示个人配置文件

**Phase 2: Git 辅助工具** ✅
- [x] 创建 .scripts/git-helpers/ 目录
- [x] 实现 git-sync-upstream.sh 脚本（56 行）
- [x] 实现 git-create-pr.sh 脚本（164 行，包含 dry-run 和用户确认）
- [x] 创建 setup-git-alias.sh 配置脚本（19 行）
- [x] 配置 git alias（sync-upstream, create-pr）
- [x] 修复 Windows 路径兼容性问题

**Phase 3: 测试和验证** ✅
- [x] 测试 git create-pr --dry-run（成功显示 PR 预览）
- [x] 验证脚本在测试分支上正常工作
- [x] 发现并记录跨分支使用问题（需要在 main 分支上也存在脚本）

**待完成**:
- [ ] 将测试分支合并到 main 或创建 PR
- [ ] 在 main 分支上验证 git sync-upstream

## Implementation Plan (small PRs)

**Phase 1: 文档和配置**
- 创建 CONTRIBUTING.md 文档
- 设置 AGENTS.md 和 CLAUDE.md 的 assume-unchanged 状态
- 记录基本工作流程

**Phase 2: Git 辅助工具**
- 创建 git alias 配置
- 实现 sync-upstream 功能
- 实现 create-pr 功能（带 dry-run 和确认）

**Phase 3: 测试和验证**
- 测试同步上游流程
- 测试 PR 创建流程（dry-run 模式）
- 更新文档补充实际使用示例
