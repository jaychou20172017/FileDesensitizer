import Foundation

final class RecoverService: @unchecked Sendable {

    func recover(maskedFileURL: URL, mappingTableURL: URL, outputDir: URL) throws -> ProcessingResult {
        try validateInputSize(maskedFileURL)
        try validateInputSize(mappingTableURL)
        try rejectLegacyFormat(maskedFileURL)
        try rejectLegacyFormat(mappingTableURL)

        let mappings = try parseMappingTable(from: mappingTableURL)
        guard !mappings.isEmpty else {
            throw ParseError.invalidStructure("映射表中没有可用的脱敏记录")
        }
        let reverseLookup = buildReverseLookup(mappings: mappings)

        let outputURL = outputDir.appendingPathComponent(
            FileFormatUtils.recoveredFileName(for: maskedFileURL)
        )

        let fileType = FileFormatUtils.detectFileType(from: maskedFileURL)

        switch fileType {
        case .excel:
            try recoverExcel(sourceURL: maskedFileURL, outputURL: outputURL, reverseLookup: reverseLookup)
        case .word, .ppt:
            throw ParseError.unsupportedFormat
        case .unknown:
            throw ParseError.unsupportedFormat
        }

        return ProcessingResult(
            fileName: maskedFileURL.lastPathComponent,
            totalFields: Set(mappings.map { $0.fieldName }).count,
            totalRows: mappings.count,
            mappings: mappings,
            outputFileURL: outputURL,
            mappingFileURL: nil
        )
    }

    private func validateInputSize(_ url: URL) throws {
        guard let fileSize = FileFormatUtils.fileSizeInBytes(at: url) else {
            throw ParseError.fileNotFound
        }
        guard FileFormatUtils.isWithinFileSizeLimit(fileSize) else {
            throw ParseError.fileTooLarge(url.lastPathComponent)
        }
    }

    private func rejectLegacyFormat(_ url: URL) throws {
        if let suggestedExtension = FileFormatUtils.modernExtension(forLegacyURL: url) {
            throw ParseError.legacyOfficeFormat(
                fileName: url.lastPathComponent,
                suggestedExtension: suggestedExtension
            )
        }
    }

    // MARK: - CSV mapping table parser

    private func parseMappingTable(from url: URL) throws -> [MappingEntry] {
        let ext = url.pathExtension.lowercased()
        if ext == "csv" {
            return try parseCSVMappingTable(from: url)
        } else if ext == "xlsx" {
            return try parseXLSXMappingTable(from: url)
        }
        throw ParseError.invalidStructure("映射表仅支持 .xlsx 或 .csv 格式")
    }

    // MARK: - CSV mapping table parser

    private func parseCSVMappingTable(from url: URL) throws -> [MappingEntry] {
        var content = try String(contentsOf: url, encoding: .utf8)
        if content.hasPrefix("\u{FEFF}") {
            content.removeFirst()
        }
        let lines = splitCSVLines(content)
        guard let header = lines.first,
              header.hasPrefix("字段名") else {
            throw ParseError.invalidStructure("CSV映射表格式不正确")
        }
        var mappings: [MappingEntry] = []
        for line in lines.dropFirst() where !line.isEmpty {
            let parts = parseCSVLine(line)
            guard parts.count >= 3, !parts[0].isEmpty else { continue }
            mappings.append(MappingEntry(
                fieldName: parts[0],
                originalValue: parts[1],
                maskedValue: parts[2]
            ))
        }
        return mappings
    }

    // MARK: - Legacy XLSX mapping table parser

    private func parseXLSXMappingTable(from url: URL) throws -> [MappingEntry] {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let script = #"""
import openpyxl, json, sys
src = sys.argv[1]; dst = sys.argv[2]
wb = openpyxl.load_workbook(src, data_only=True)
ws = wb.active
headers = []
for c in range(1, ws.max_column + 1):
    v = ws.cell(row=1, column=c).value
    headers.append(str(v) if v else "")
try:
    fn_idx = headers.index("字段名")
    orig_idx = headers.index("原始值")
    masked_idx = headers.index("脱敏值")
except ValueError:
    print("[]")
    sys.exit(0)
entries = []
for r in range(2, ws.max_row + 1):
    fn = ws.cell(row=r, column=fn_idx + 1).value
    orig = ws.cell(row=r, column=orig_idx + 1).value
    masked = ws.cell(row=r, column=masked_idx + 1).value
    if fn and orig is not None and masked is not None:
        entries.append([str(fn), str(orig), str(masked)])
json.dump(entries, open(dst, 'w'))
"""#
        let status = try runPython(script: script, args: [url.path, jsonURL.path])
        guard status == 0 else {
            throw ParseError.invalidStructure("XLSX映射表读取失败")
        }
        let jsonData = try Data(contentsOf: jsonURL)
        let rows = try JSONSerialization.jsonObject(with: jsonData) as? [[String]] ?? []
        return rows.compactMap { row in
            row.count >= 3 ? MappingEntry(fieldName: row[0], originalValue: row[1], maskedValue: row[2]) : nil
        }
    }

    // Split CSV content into logical lines, respecting quoted fields spanning multiple physical lines
    private func splitCSVLines(_ content: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var inQuotes = false
        var previousWasQuote = false

        for char in content {
            if previousWasQuote && char != "\"" {
                inQuotes = false
                previousWasQuote = false
            }

            if char == "\"" {
                if inQuotes {
                    if previousWasQuote {
                        current.append("\"")
                        previousWasQuote = false
                    } else {
                        previousWasQuote = true
                    }
                } else {
                    inQuotes = true
                    previousWasQuote = false
                }
            } else if char == "\n" && !inQuotes {
                lines.append(current)
                current = ""
            } else if char == "\r" && !inQuotes {
                continue
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var previousWasQuote = false

        for char in line {
            if previousWasQuote && char != "\"" {
                inQuotes = false
                previousWasQuote = false
            }

            if char == "\"" {
                if inQuotes {
                    if previousWasQuote {
                        current.append("\"")
                        previousWasQuote = false
                    } else {
                        previousWasQuote = true
                    }
                } else {
                    inQuotes = true
                    previousWasQuote = false
                }
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    private func buildReverseLookup(mappings: [MappingEntry]) -> [String: String] {
        var dict: [String: String] = [:]
        for m in mappings {
            dict["\(m.fieldName)|\(m.maskedValue)"] = m.originalValue
        }
        return dict
    }

    // MARK: - Excel recovery via openpyxl

    private func recoverExcel(sourceURL: URL, outputURL: URL, reverseLookup: [String: String]) throws {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let lookupData = reverseLookup.map { ["key": $0.key, "originalValue": $0.value] }
        let jsonData = try JSONSerialization.data(withJSONObject: lookupData, options: [])
        try jsonData.write(to: jsonURL)

        let script = #"""
import openpyxl, json, sys
src = sys.argv[1]; jp = sys.argv[2]; dst = sys.argv[3]
with open(jp) as f:
    data = json.load(f)
reverse_map = {}
for item in data:
    key = item["key"]
    if "|" in key:
        fn, masked = key.split("|", 1)
        reverse_map[(fn, masked)] = item["originalValue"]
wb = openpyxl.load_workbook(src, data_only=False)
header_map = {}
for sn in wb.sheetnames:
    ws = wb[sn]
    for c in range(1, ws.max_column + 1):
        v = ws.cell(row=1, column=c).value
        if v:
            header_map.setdefault(str(v), []).append((sn, c))
cnt = 0
for (fn, masked), orig in reverse_map.items():
    for sn, col in header_map.get(fn, []):
        ws = wb[sn]
        for r in range(2, ws.max_row + 1):
            cell = ws.cell(row=r, column=col)
            if cell.value is not None and str(cell.value) == str(masked):
                cell.value = orig
                cnt += 1
if reverse_map and cnt == 0:
    print("映射表与脱敏文件不匹配，未找到可恢复的单元格", file=sys.stderr)
    sys.exit(3)
wb.save(dst)
print(f"RECOVERED:{cnt}")
"""#

        let status = try runPython(script: script, args: [sourceURL.path, jsonURL.path, outputURL.path])
        guard status == 0 else {
            throw ParseError.invalidStructure("数据恢复失败")
        }
    }

    // MARK: - Word/PPT recovery via XML manipulation

    private func recoverOOXML(sourceURL: URL, outputURL: URL, reverseLookup: [String: String]) throws {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let lookupData = reverseLookup.map { ["key": $0.key, "originalValue": $0.value] }
        let jsonData = try JSONSerialization.data(withJSONObject: lookupData, options: [])
        try jsonData.write(to: jsonURL)

        let ext = sourceURL.pathExtension.lowercased()
        let script = #"""
import json, sys, os, zipfile, tempfile, shutil
from xml.etree import ElementTree as ET

src = sys.argv[1]; jp = sys.argv[2]; dst = sys.argv[3]; ftype = sys.argv[4]

with open(jp) as f:
    data = json.load(f)
reverse_map = {}
for item in data:
    key = item["key"]
    if "|" in key:
        fn, masked = key.split("|", 1)
        reverse_map[(fn, masked)] = item["originalValue"]

tmpd = tempfile.mkdtemp()
with zipfile.ZipFile(src, 'r') as zf:
    zf.extractall(tmpd)

def fix_text(element):
    """Replace ALL masked values found in element text, return count"""
    if not element.text:
        return 0
    c = 0
    # Sort by masked value length descending to avoid shorter matches corrupting longer ones
    sorted_items = sorted(reverse_map.items(), key=lambda x: len(x[0][1]), reverse=True)
    for (fn, masked), orig in sorted_items:
        if masked in element.text:
            element.text = element.text.replace(masked, orig)
            c += 1
    return c

cnt = 0
xml_files = []
for dirpath, dirnames, filenames in os.walk(tmpd):
    for fn in filenames:
        if fn.endswith(".xml"):
            xml_files.append(os.path.join(dirpath, fn))

xml_files.sort()
for xpath in xml_files:
    try:
        tree = ET.parse(xpath)
        root = tree.getroot()
        modified = False
        for el in root.iter():
            tag = el.tag.split("}")[-1] if "}" in el.tag else el.tag
            if tag == "t":
                c = fix_text(el)
                if c:
                    cnt += c
                    modified = True
        if modified:
            tree.write(xpath, xml_declaration=True, encoding="UTF-8")
    except Exception:
        pass

if reverse_map and cnt == 0:
    shutil.rmtree(tmpd)
    print("映射表与脱敏文件不匹配，未找到可恢复的文本", file=sys.stderr)
    sys.exit(3)

with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zout:
    for dirpath, dirnames, filenames in os.walk(tmpd):
        for fn in filenames:
            fpath = os.path.join(dirpath, fn)
            aname = os.path.relpath(fpath, tmpd)
            zout.write(fpath, aname)

shutil.rmtree(tmpd)
print(f"RECOVERED:{cnt}")
"""#

        let status = try runPython(script: script, args: [sourceURL.path, jsonURL.path, outputURL.path, ext])
        guard status == 0 else {
            throw ParseError.invalidStructure("数据恢复失败")
        }
    }

    private func runPython(script: String, args: [String]) throws -> Int32 {
        let process = Process()
        try PythonRuntime.configure(process)
        process.arguments = ["-c", script] + args
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? ""
            throw ParseError.invalidStructure("数据恢复失败: \(errMsg)")
        }
        return process.terminationStatus
    }
}
