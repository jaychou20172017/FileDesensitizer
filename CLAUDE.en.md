# Developer guidance — English companion
[中文](CLAUDE.md)

This is a companion translation of the existing developer guide, not a replacement policy. Follow the original staged requirements/design/execution documents. Update requirements before changing behavior, validate each phase and keep dated developer logs. Documentation-only translation does not establish a fresh build or application acceptance.

Project requirements, technical specification, design and staged execution references are under docs/; English editions are indexed at [docs/en/index.md](docs/en/index.md). Treat historical workstation paths as original development context rather than portable installation requirements. Preserve local-only processing/storage boundaries, supported formats and existing tests.

For FileDesensitizer, change one module at a time with at most three files per step, compile after code changes and follow system-native design rules. The current product accepts .xlsx only. macOS uses SwiftUI/Swift and local Excel processing; Windows has its own Electron code and tests.
