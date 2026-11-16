# Windows Manual Test Checklist

[中文](../windows-manual-test-checklist.md)

Use Windows 10/11 x64, the complete packaged app and a safe copy of the original acceptance fixture (historically `Windows验收样例.xlsx`; it may not be distributed in this repository). Fully extract the ZIP and launch FileDesensitizer.exe. Check a usable window and both processing/recovery pages; assess any OS trust warning against the verified source.

For the original 11-column, five-row fixture expect eight sensitive selections: name, mobile, ID, email, bank card, supplier, landline and collaborator names; ID/address/notes ordinary columns are not selected. Preserve full ID/card digits. Processing expects 40 replaced cells, two output workbooks and 31 mapping rows excluding headers. All repeated source values must map consistently across rows/name columns; address/notes remain unchanged. These counts apply only to that original fixture, not arbitrary files.

Repeat to the same directory: list both conflicting outputs; Cancel must preserve files, explicit Overwrite must work. Recover with the matching mapping: 40 cells and all 11×5 original data restored. Repeat recovery and check overwrite confirmation. .docx/.pptx/.xls must not proceed. Mark pass only after actually executing all checks; record failed step/message/screenshot and preserve fixture/output copies. No new manual test was run in this translation update.
