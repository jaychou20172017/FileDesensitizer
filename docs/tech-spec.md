# 技术规格书 — 文件脱敏工具

## 运行环境

- **平台**：macOS 14 (Sonoma) 及以上
- **语言**：Swift 6.3
- **UI 框架**：SwiftUI
- **IDE**：Xcode 26.6
- **架构**：单进程桌面应用，MVVM

### Windows 版本

- **平台**：Windows 10/11 x64
- **技术栈**：Electron + HTML/CSS/JavaScript
- **Excel 引擎**：ExcelJS，处理 `.xlsx` 的读取、字段分析、写回及映射表
- **安全边界**：启用 context isolation、禁用 renderer Node integration，仅通过 preload 暴露受控文件接口
- **交付形式**：免安装 ZIP，解压后双击 `FileDesensitizer.exe`
- **图标**：复用 macOS 版 1024×1024 主图，生成 Windows 多尺寸 `.ico`

## 项目结构

```
FileDesensitizer/
├── FileDesensitizer.xcodeproj
├── FileDesensitizer/
│   ├── App.swift                      # 应用入口
│   ├── ContentView.swift              # 主视图（Tab切换）
│   ├── ViewModels/
│   │   ├── DesensitizeViewModel.swift
│   │   └── RecoverViewModel.swift
│   ├── Views/
│   │   ├── DesensitizeView.swift      # 脱敏处理页
│   │   ├── RecoverView.swift          # 数据恢复页
│   │   ├── FieldSelectionView.swift   # 字段选择列表
│   │   ├── PreviewView.swift          # 前后对比预览
│   │   └── DropZoneView.swift         # 拖拽上传区域
│   ├── Services/
│   │   ├── FileParserService.swift    # Excel 文件解析
│   │   ├── SensitiveDetector.swift    # 敏感信息检测
│   │   ├── DesensitizeService.swift   # 脱敏处理
│   │   └── RecoverService.swift       # 数据恢复
│   ├── Models/
│   │   ├── FieldInfo.swift            # 字段信息
│   │   ├── MappingEntry.swift         # 映射条目
│   │   └── ProcessingResult.swift     # 处理结果
│   └── Utilities/
│       ├── RegexPatterns.swift        # 敏感信息正则
│       └── FileFormatUtils.swift      # 文件格式处理
├── docs/
├── devlog/
└── README.md
```

## 架构分层

```
┌─────────────────────────────────┐
│  Views (SwiftUI)                │  ← 用户交互层
├─────────────────────────────────┤
│  ViewModels (ObservableObject)  │  ← 状态管理 + 业务编排
├─────────────────────────────────┤
│  Services                       │  ← 核心业务逻辑
├─────────────────────────────────┤
│  Models                         │  ← 数据结构
├─────────────────────────────────┤
│  Utilities                      │  ← 工具函数
└─────────────────────────────────┘
```

**数据流**：View → ViewModel → Service → Model → ViewModel → View

## 第三方依赖

| 库 | 用途 | 引入方式 |
|----|------|----------|
| [CoreXLSX](https://github.com/CoreOffice/CoreXLSX) | Excel .xlsx 读写 | SPM |
| CPython 3.13.15 | 执行本地 OOXML 处理脚本 | 内置 python-build-standalone arm64 `install_only_stripped` 运行时 |
| openpyxl 3.1.5 + defusedxml 0.7.1 | Excel 解析、原结构写回、XLSX 映射表与 XML 安全加固 | 固定版本安装到内置运行时 |

## 关键技术点

### Excel 处理
- 读取：本地 openpyxl 解析 .xlsx，读取所有 Sheet/行列/单元格及公式缓存值
- 写入：本地 openpyxl 按原工作簿结构替换选中字段

### 格式边界
- 当前版本仅开放 `.xlsx` 的解析、脱敏和恢复
- `.xls` 选择后返回中文提示，要求另存为 `.xlsx`
- Word（`.doc`/`.docx`）和 PowerPoint（`.ppt`/`.pptx`）处理暂时下线，上传时统一提示当前仅支持 `.xlsx`
- 不依赖 Microsoft Office、LibreOffice 或 iWork 自动转换，避免外部应用权限和离线环境差异

### 敏感数据检测
- 检测 Excel 单元格中的手机号、身份证、邮箱、银行卡、姓名、供应商名称、固话 7 种敏感类型（见 requirements.md），地址不参与脱敏
- 对每列的样本值（前 N 行）逐一检测
- 标记匹配率超过阈值的列为敏感字段
- 供应商名称使用公司法定名称后缀和明确表头联合识别；正文姓名只接受由分隔符组成的高置信度人员列表

### 假名化替换
- 相同原值映射到相同假名值（确定性映射）
- 保持格式特征：手机号→随机11位数字，邮箱→随机用户名@随机域名
- 使用 SHA256(原值 + 盐) 作为种子生成本地化的假名值
- 映射表：字段名 | 原值 | 脱敏值

### 数据恢复
- 读取映射表，构建 脱敏值→原值 的逆向索引
- 遍历脱敏文件，用逆向索引替换

## 非功能性要求
- 文件处理上限 100MB
- 大文件使用流式/分页处理避免内存溢出
- 错误处理：格式不支持、文件损坏、映射表不匹配时给出中文友好提示

## 发布约束
- 当前 Debug/Release 构建均面向 Apple Silicon，最低 macOS 14
- Release 应用类别为 Productivity
- Release 内置 77MB arm64 CPython 运行时，应用包约 81MB，不依赖目标 Mac 的 `/usr/bin/python3` 或用户 site-packages
- 内置运行时由 `scripts/prepare-python-runtime.sh` 按版本和 SHA-256 固定生成；进程设置 `PYTHONHOME`、`PYTHONNOUSERSITE=1` 和 `PYTHONDONTWRITEBYTECODE=1`
- 第三方许可证声明随应用资源发布；正式对外分发仍需 Developer ID 签名和 Apple 公证

## 分发产物
- 使用 `scripts/build-distribution.sh` 生成 Apple Silicon DMG，内容包含应用、Applications 快捷方式和安装说明
- 无 Developer ID 证书时生成 ad-hoc 签名测试包，接收方首次运行可能需要右键“打开”
- 面向普通用户直接双击安装的正式包必须使用 Developer ID Application 签名，并提交 Apple 公证、装订公证票据
- Windows 使用 Electron Packager 生成 x64 程序目录并压缩为 ZIP；正式外发免 SmartScreen 警告仍需 Windows Authenticode 代码签名证书
