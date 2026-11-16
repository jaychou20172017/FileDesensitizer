# File Desensitizer
[中文](README.md) | English

A local Excel pseudonymization and recovery application for macOS and Windows. Only `.xlsx` is currently supported. Word, PowerPoint and legacy `.xls` are not supported; convert `.xls` in office software first.

## Features
- Detect mobile numbers, identity numbers, email addresses, bank cards, names, supplier names and landlines. Addresses are not detected or selected by default.
- Choose a worksheet and fields. The same original value maps consistently to the same replacement.
- Export a pseudonymized workbook and separate reversible mapping workbook; recover into a new workbook while keeping the input.
- Preview changes locally. No file upload or network processing.
- List existing output conflicts and write only after explicit overwrite confirmation.

## Platforms and development
macOS: Swift/SwiftUI, Apple Silicon, macOS 14+. Windows: Electron/ExcelJS, Windows 10/11 x64.

```sh
cd FileDesensitizer
./scripts/prepare-python-runtime.sh
./run-core-tests.sh
./run-integration-test.sh
./scripts/build-distribution.sh
```
Open `FileDesensitizer/FileDesensitizer.xcodeproj` in Xcode. For Windows:
```sh
cd Windows
npm ci
npm test
npm start
npm run package:win
```
Packages are generated in root `dist/`; dependencies and build outputs are not committed. Runtime preparation uses pinned versions. See [English documentation](docs/en/index.md) for requirements, architecture, design and acceptance instructions.

## Privacy and distribution
Mappings can recover original data: store them separately and restrict access. This is reversible pseudonymization, not a guarantee of anonymization. Current packages lack production Apple Developer ID notarization/Windows Authenticode signing; complete platform signing before normal external distribution. Existing third-party notices remain applicable.

Documentation is bilingual; this update does not translate the application UI, filenames, tests or historical development logs. It does not claim newly executed platform acceptance.
## 许可 / License

Copyright (c) 2026 Zhou Jie。非商业用途及企业内部使用免费；对外销售、收费服务、商业产品集成及商业托管等须事先取得书面授权。联系：[3504264104@qq.com](mailto:3504264104@qq.com)。

Noncommercial and internal business use are free. External sales, paid services, commercial product integration and commercial hosting require prior written authorization from Zhou Jie.

完整条款 / Full terms: [LICENSE](LICENSE). [English translation](LICENSE.en.md)（中文准据 / Chinese governs）. [商业授权 / Commercial licensing](COMMERCIAL-LICENSE.md).

本许可仅覆盖权利人有权许可的项目内容，不改变第三方组件许可。新增许可不追溯撤销先前已合法取得的其他许可；历史发布包不会自动更新。This license does not replace third-party terms or revoke earlier lawfully granted rights; old release archives are not automatically updated.
