# 开发执行步骤 — 文件脱敏工具

## 开发原则

1. **每次只做一个模块**，编译通过且功能验证后再进入下一步
2. **核心逻辑先跑通**，UI 润色放在最后
3. **禁止一口气写全部代码**，每一步改动 ≤ 3 个文件

---

## Phase 1：项目骨架（预计 1 轮）

### Step 1.1 创建 Xcode 项目
- [x] 创建 Xcode 项目 `FileDesensitizer`，macOS App 模板，SwiftUI
- [x] 配置最低系统版本 macOS 14
- [x] 添加 CoreXLSX SPM 依赖

### Step 1.2 创建目录和空文件
- [x] 按 tech-spec.md 创建所有目录
- [x] 创建 App.swift / ContentView.swift（骨架版，仅显示 Tab）

### Step 1.3 验证
- [x] Build 通过
- [x] 运行显示空窗口 + 两个 Tab 标签

---

## Phase 2：数据模型 + 工具层（预计 1 轮）

### Step 2.1 数据模型
- [x] `FieldInfo.swift` — 字段名、来源、敏感类型、选中状态
- [x] `MappingEntry.swift` — 字段名、原值、脱敏值、Identifiable
- [x] `ProcessingResult.swift` — 统计信息 + 映射列表

### Step 2.2 工具
- [x] `RegexPatterns.swift` — 7 种敏感信息正则枚举
- [x] `FileFormatUtils.swift` — 文件类型判断、命名规则生成

### Step 2.3 验证
- [x] Build 通过
- [x] 模型编译无报错

---

## Phase 3：服务层（分 4 小步，每步验证）

### Step 3.1 Excel 解析 + 脱敏 + 恢复
- [x] `FileParserService.swift` — Excel 读取
- [x] `SensitiveDetector.swift` — 敏感信息检测
- [x] `DesensitizeService.swift` — 脱敏 + 映射表生成
- [x] `RecoverService.swift` — 恢复
- [x] 写单元测试验证核心逻辑

### Step 3.2 Word 解析
- [x] 扩展 FileParserService 支持 .docx 解析
- [x] 提取表格 + 正则扫描文本
- [x] 2026-09-26：因处理效果未达到发布要求，当前版本已下线 Word 解析、脱敏和恢复入口

### Step 3.3 PPT 解析
- [x] 扩展 FileParserService 支持 .pptx 解析
- [x] 提取表格 + 正则扫描文本
- [x] 2026-09-26：因处理效果未达到发布要求，当前版本已下线 PPT 解析、脱敏和恢复入口

### Step 3.4 验证
- [x] Build 通过
- [x] 单元测试全部通过

---

## Phase 4：ViewModel + UI（分 5 小步，每步验证）

### Step 4.1 DropZoneView
- [x] 拖拽文件上传组件

### Step 4.2 FieldSelectionView
- [x] 字段列表 + checkbox + 敏感标记
- [x] 全选/取消全选

### Step 4.3 DesensitizeView + ViewModel
- [x] 脱敏 Tab 完整流程

### Step 4.4 RecoverView + ViewModel
- [x] 恢复 Tab 完整流程

### Step 4.5 PreviewView
- [x] 前后对比表格 + 分页

---

## Phase 5：集成 + 打磨（预计 1 轮）

- [x] ContentView 串联完整流程
- [ ] 暗色模式确认
- [x] 错误提示完善
- [x] 大文件性能测试
- [x] 内置 Python/openpyxl 运行时，不依赖目标 Mac 的开发环境
- [x] 产品范围收敛为仅支持 `.xlsx`，Word/PPT 文件给出不支持提示
- [x] 增加 DMG 分发打包流程和接收方安装说明
- [ ] 配置 Developer ID Application 证书并完成 Apple 公证
- [ ] 最终验证

---

## Phase 6：Windows 版本

- [x] 实现 Windows `.xlsx` 字段分析、脱敏和恢复核心逻辑
- [x] 实现 Electron 桌面界面及安全的主进程/渲染进程桥接
- [x] 复用 macOS 图标生成 Windows `.ico`
- [x] 生成 Windows 10/11 x64 免安装 ZIP
- [ ] 完成 Windows 实机手动验收
- [ ] 正式分发前配置 Windows Authenticode 代码签名

---

## 验证标准

每一步完成后必须满足：
1. `xcodebuild build` 无错误
2. 新增代码与已有逻辑无冲突
3. 更新 devlog 记录进度
