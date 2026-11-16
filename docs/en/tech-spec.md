# Tech Spec

[中文](../tech-spec.md)

macOS uses SwiftUI/MVVM: Views → ViewModels → Services → Models, with utility regex/file helpers. The documented toolchain is Swift 6.3/Xcode 26.6; this translation does not assert a new build was run. CoreXLSX is listed as an SPM dependency; local OOXML read/write uses pinned bundled CPython 3.13.15 with openpyxl 3.1.5 and defusedxml 0.7.1. Preserve original workbook structure while replacing selected fields; do not rely on Office/LibreOffice/iWork automatic conversion.

Windows uses Electron/HTML/CSS/JavaScript and ExcelJS. Enable context isolation, disable renderer Node integration and expose controlled preload file APIs. Package x64 directories into ZIPs and reuse the icon master as multi-size .ico.

Detection samples columns and uses thresholds; address exclusion and high-confidence names reduce false positives. Deterministic localized pseudonyms use a SHA256(original+salt) seed; mapping fields identify original/replacement and field name. Recovery builds a reverse index. This is reversible replacement, not cryptographic anonymization.

Documented nonfunctional targets include 100 MB files, streamed/paged processing and friendly errors for unsupported/corrupt/mismatched data. Release targets Apple Silicon macOS 14+, Productivity category and pinned arm64 runtime isolated through PYTHONHOME/PYTHONNOUSERSITE/PYTHONDONTWRITEBYTECODE. The original spec estimates runtime/app sizes; actual packages vary. Runtime licenses remain bundled. build-distribution.sh produces DMG; ad-hoc packages are testing artifacts. Production distribution requires Developer ID signing/notarization/stapling, and Windows Authenticode where applicable. No new build/signing claim accompanies this documentation update.
