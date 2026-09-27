# CLAUDE.md — 文件脱敏工具项目指引

## 项目概述

macOS 原生文件脱敏工具，SwiftUI + Swift 开发。当前仅支持 Excel `.xlsx` 文件的字段级假名化脱敏与数据恢复；Word/PPT 支持已暂时下线。

## 标准文件路径

开发过程中，所有决策和规范均以以下文件为准：

| 文件 | 路径 | 说明 |
|------|------|------|
| 产品需求 | [docs/requirements.md](docs/requirements.md) | 功能需求、设计决策 |
| 技术规格 | [docs/tech-spec.md](docs/tech-spec.md) | 架构、依赖、关键技术方案 |
| 设计规范 | [docs/design-standards.md](docs/design-standards.md) | UI/UX 色彩、字体、布局、交互 |
| 执行步骤 | [docs/execution-steps.md](docs/execution-steps.md) | 分阶段开发步骤和验证标准 |
| 开发日志 | [devlog/](devlog/) | 每日开发记录 |

## 工作约定

1. **每步改动 ≤ 3 个文件**，编译通过后再继续下一步
2. **严格遵循执行步骤**（execution-steps.md），不跳步不跨 Phase
3. **每天结束**自动在 devlog/ 下写入当日日志（YYYY-MM-DD.md）
4. **需求/设计变更**先更新对应 docs/ 文件，再改代码
5. **所有操作在项目目录下进行**：`/Users/jiezhou/个人/AI/文件脱敏软件/`
6. **编译验证**：每次代码改动后用 `xcodebuild build` 确认无报错
7. **UI 变更**：参照 design-standards.md 的色彩/字体/布局规范

## 快速命令

```bash
# 项目目录
cd "/Users/jiezhou/个人/AI/文件脱敏软件"

# 编译验证
xcodebuild -project FileDesensitizer.xcodeproj -scheme FileDesensitizer build 2>&1 | tail -20

# 查看今日日志
cat devlog/$(date +%Y-%m-%d).md
```
