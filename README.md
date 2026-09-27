# 文件脱敏工具

一个面向 macOS 与 Windows 的本地 Excel 文件脱敏应用。当前版本仅支持 `.xlsx`，可识别敏感字段、生成可逆脱敏文件和映射表，并使用映射表恢复原始内容。

## 主要功能

- 识别手机号、身份证号、邮箱、银行卡号、姓名、供应商名称和固定电话
- 地址默认不识别、不脱敏
- 用户可以选择需要处理的工作表和字段
- 相同原值始终生成相同脱敏值
- 输出脱敏工作簿和独立映射表
- 使用映射表生成恢复工作簿
- 文件只在本地处理，不上传网络
- 目标文件已存在时先列出冲突文件并确认是否覆盖

## 支持平台

| 平台 | 技术 | 系统要求 |
| --- | --- | --- |
| macOS | SwiftUI、Swift、内置 Python/openpyxl | macOS 14+，Apple Silicon |
| Windows | Electron、ExcelJS | Windows 10/11，x64 |

Word、PowerPoint 和旧版 `.xls` 当前不支持。

## 项目结构

```text
FileDesensitizer/   macOS 工程、测试和打包脚本
Windows/            Windows Electron 工程、测试和打包脚本
docs/               产品需求、技术规格和验收清单
design/             应用图标母版
devlog/             开发日志
distribution/       安装说明
```

## macOS 开发

首次构建前准备固定版本的 Python 运行时：

```bash
cd FileDesensitizer
./scripts/prepare-python-runtime.sh
./run-core-tests.sh
./run-integration-test.sh
```

随后使用 Xcode 打开 `FileDesensitizer/FileDesensitizer.xcodeproj`。

生成 macOS 分发包：

```bash
cd FileDesensitizer
./scripts/build-distribution.sh
```

## Windows 开发

```bash
cd Windows
npm ci
npm test
npm start
```

在 macOS 或 Windows 上生成 Windows x64 免安装包：

```bash
cd Windows
npm run package:win
```

输出文件位于项目根目录的 `dist/`。构建产物和依赖目录不提交到 Git；使用上述脚本可以重新生成。

## 安全提示

脱敏映射表可以恢复原始数据。请将映射表与脱敏文件分开保存，并限制映射表的访问权限。

当前分发包未配置 Apple Developer ID 公证或 Windows Authenticode 正式签名。面向外部用户正式发布前应完成相应平台的代码签名流程。
