# 重组 Trellis spec 目录结构

## Goal

将 Flutter 项目规范从错误的位置（`core/doh_proxy/`）移动到正确的 monorepo 结构，确保 Trellis 子代理能够加载正确的项目规范。

## What I already know

**当前问题**：
- `core/doh_proxy` 是一个 Rust DOH 代理的 git submodule（未初始化）
- 所有 Flutter/Dart 代码都在主项目的 `lib/` 目录下
- 当前 Flutter 规范错误地放在了 `.trellis/spec/core/doh_proxy/` 下
- Trellis 显示的包名是 `core/doh_proxy (submodule)`，但实际应该是 `fluxdo`

**已填充的规范文件**：
- Backend: 6 个文件
- Frontend: 7 个文件
- 总计：13 个规范文件 + 2 个 index 文件 = 15 个 Markdown 文件

**目标结构**：
```
.trellis/spec/
├── fluxdo/                     # 主 Flutter 项目
│   ├── backend/
│   └── frontend/
└── core/
    └── doh_proxy/              # Rust DOH 代理（保留空结构）
```

## Assumptions (temporary)

- 需要更新 Trellis 包配置（packages.json 或类似配置文件）
- 可能需要更新 implement.jsonl 和 check.jsonl 文件路径引用
- 旧的 core/doh_proxy spec 应该保留为空模板（不删除）

## Open Questions

~~1. Trellis 的包配置在哪里定义？~~ **已找到**：`.trellis/config.yaml`
2. 是否需要更新 `.trellis/.template-hashes.json` 中的文件路径？
3. 是否需要保留 `core/doh_proxy` 空 spec 结构？

## Requirements (evolving)

- [x] 移动 Flutter 规范文件：`.trellis/spec/core/doh_proxy/` → `.trellis/spec/fluxdo/`
- [x] 更新 Trellis 包配置，将默认包从 `core/doh_proxy` 改为 `fluxdo`
- [x] 更新所有文件路径引用（`.trellis/.template-hashes.json`）
- [x] 保留 `core/doh_proxy` 空结构（供未来 Rust DOH 代理规范使用）
- [x] 验证 Trellis 能正确识别新的包结构

## Acceptance Criteria (evolving)

- [x] `python ./.trellis/scripts/get_context.py --mode packages` 显示 `fluxdo` 为默认包
- [x] 所有 Flutter 规范文件位于 `.trellis/spec/fluxdo/` 下
- [x] `core/doh_proxy` spec 目录保留，包含空白模板文件
- [x] 文件引用路径全部更新为正确的位置

## Definition of Done

- 目录结构重组完成
- Trellis 配置更新完成
- 验证命令输出正确
- 提交 git 变更

## Out of Scope (explicit)

- 不填充 Rust DOH 代理的规范（另建任务）
- 不修改 Flutter 规范内容
- 不更新已归档任务的 jsonl 文件（除非影响当前功能）

## Decision (ADR-lite)

**Context**: Flutter 项目规范被错误地放在了 Rust DOH 代理的 submodule 路径下，导致 Trellis 将 `core/doh_proxy` 识别为默认包，而实际上主项目是 `fluxdo`。

**Decision**:
1. 采用 monorepo 结构：`fluxdo` 作为主包（默认），`core/doh_proxy` 保留为 submodule
2. 移动 Flutter 规范到正确的 `fluxdo` 包下
3. 为 `core/doh_proxy` 创建空白模板，等待填充 Rust 规范

**Consequences**:
- ✅ Trellis 现在能正确识别主项目 `fluxdo`
- ✅ 子代理将加载正确的 Flutter 规范
- ✅ 保留了 `core/doh_proxy` 结构，不影响未来的 Rust 开发规范
- ⚠️ 需要注意：已归档的 bootstrap 任务的 jsonl 文件仍指向旧路径，但不影响当前功能

## Technical Notes

**Trellis 配置文件**：`.trellis/config.yaml`
```yaml
packages:
  core/doh_proxy:
    path: core/doh_proxy
    type: submodule
default_package: core/doh_proxy
```

**需要更新为**：
```yaml
packages:
  fluxdo:
    path: .
  core/doh_proxy:
    path: core/doh_proxy
    type: submodule
default_package: fluxdo
```

**文件清单**：
- Backend: index.md, database-guidelines.md, directory-structure.md, error-handling.md, logging-guidelines.md, quality-guidelines.md
- Frontend: index.md, component-guidelines.md, directory-structure.md, hook-guidelines.md, quality-guidelines.md, state-management.md, type-safety.md

**其他需要更新的文件**：
- `.trellis/.template-hashes.json` - 更新文件路径引用

**约束**：
- Git submodule `core/doh_proxy` 目前未初始化（目录为空）
- 项目根 pubspec.yaml 名称为 `fluxdo`
