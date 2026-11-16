# Requirements

[中文](../requirements.md)

Only `.xlsx` is accepted through drag/drop or selection. Show filename/size/type and handle one file at a time. Legacy .xls must be converted externally; Word/PowerPoint remain disabled with friendly messages. Read sheets and let users select a sheet and fields. Detect mobile/ID/email/bank card/name/supplier/landline data; addresses are excluded. Supplier names use legal-name suffixes/clear headers; personal names in free text need high-confidence delimited lists. Display all fields, highlight/recommend sensitive ones, allow select/deselect all.

Pseudonymization is reversible, format-preserving and deterministic for repeated original values. Export a processed workbook plus separate mapping workbook. Recover from the processed file and matching map into a new file, retaining the processed input. Preview before/after data in-app. Native save dialogs suggest filenames; list all existing conflicts and write only after explicit overwrite. Default filenames retain the original Chinese suffixes `_脱敏`, `_脱敏映射表.xlsx`, `_脱敏恢复版`. Processing is local. macOS uses SwiftUI/Swift, macOS 14+; Windows uses Electron, Windows 10/11 x64.
