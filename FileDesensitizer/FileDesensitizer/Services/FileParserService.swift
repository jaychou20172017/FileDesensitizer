import Foundation
import CoreXLSX

struct ParsedFile {
    let fileName: String
    let fileType: FileFormatUtils.FileType
    var sheets: [SheetData]
    var textContent: String
}

struct SheetData {
    let name: String
    let headers: [String]
    let rows: [[String]]
}

enum ParseError: LocalizedError {
    case unsupportedFormat
    case legacyOfficeFormat(fileName: String, suggestedExtension: String)
    case fileNotFound
    case fileTooLarge(String)
    case invalidStructure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "当前版本仅支持 .xlsx Excel 文件，Word 和 PowerPoint 暂不支持"
        case .legacyOfficeFormat(let fileName, let suggestedExtension):
            return "“\(fileName)”是旧版 Office 格式，请先另存为 .\(suggestedExtension) 后再处理"
        case .fileNotFound:
            return "文件不存在或无法访问"
        case .fileTooLarge(let fileName):
            return "文件“\(fileName)”超过 100MB 处理上限"
        case .invalidStructure(let detail):
            return "文件结构异常：\(detail)"
        }
    }
}

final class FileParserService: @unchecked Sendable {

    func parse(url: URL) throws -> ParsedFile {
        guard let fileSize = FileFormatUtils.fileSizeInBytes(at: url) else {
            throw ParseError.fileNotFound
        }
        guard FileFormatUtils.isWithinFileSizeLimit(fileSize) else {
            throw ParseError.fileTooLarge(url.lastPathComponent)
        }
        if let suggestedExtension = FileFormatUtils.modernExtension(forLegacyURL: url) {
            throw ParseError.legacyOfficeFormat(
                fileName: url.lastPathComponent,
                suggestedExtension: suggestedExtension
            )
        }

        let type = FileFormatUtils.detectFileType(from: url)
        switch type {
        case .excel:
            return try parseExcel(url: url)
        case .word, .ppt:
            throw ParseError.unsupportedFormat
        case .unknown:
            throw ParseError.unsupportedFormat
        }
    }

    // MARK: - Excel (.xlsx)

    private func parseExcel(url: URL) throws -> ParsedFile {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let script = #"""
import json, sys, openpyxl
from datetime import date, datetime, time

src = sys.argv[1]; dst = sys.argv[2]
wb = openpyxl.load_workbook(src, data_only=True, read_only=True)

def cell_text(value):
    if value is None:
        return ""
    if isinstance(value, (date, datetime, time)):
        return value.isoformat()
    return str(value)

sheets = []
for ws in wb.worksheets:
    rows = [
        [cell_text(cell.value) for cell in row]
        for row in ws.iter_rows(
            min_row=1,
            max_row=ws.max_row,
            min_col=1,
            max_col=ws.max_column
        )
    ]
    headers = rows[0] if rows else []
    sheets.append({
        "name": ws.title,
        "headers": headers,
        "rows": rows[1:] if rows else []
    })

with open(dst, "w") as f:
    json.dump({"sheets": sheets}, f, ensure_ascii=False)
"""#

        let status = try runPython(script: script, args: [url.path, jsonURL.path])
        guard status == 0 else {
            throw ParseError.invalidStructure("无法打开 Excel 文件")
        }

        let jsonData = try Data(contentsOf: jsonURL)
        guard let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let sheetsJSON = result["sheets"] as? [[String: Any]] else {
            throw ParseError.invalidStructure("Excel 解析结果异常")
        }
        let sheets = sheetsJSON.compactMap { sheet -> SheetData? in
            guard let name = sheet["name"] as? String,
                  let headers = sheet["headers"] as? [String],
                  let rows = sheet["rows"] as? [[String]] else { return nil }
            return SheetData(name: name, headers: headers, rows: rows)
        }

        return ParsedFile(
            fileName: url.lastPathComponent,
            fileType: .excel,
            sheets: sheets,
            textContent: ""
        )
    }

    // Build a mapping from worksheet file path to real sheet name
    private func parseSheetNameMap(from url: URL) throws -> [String: String] {
        let extractedDir = try extractZip(url: url)
        defer { try? FileManager.default.removeItem(at: extractedDir) }

        // Parse xl/_rels/workbook.xml.rels for rId -> target mapping
        let relsPath = extractedDir.appendingPathComponent("xl/_rels/workbook.xml.rels")
        var rIdToTarget: [String: String] = [:]
        if FileManager.default.fileExists(atPath: relsPath.path) {
            let relsParser = RelsXMLParser()
            let xmlParser = XMLParser(contentsOf: relsPath)!
            xmlParser.delegate = relsParser
            xmlParser.parse()
            rIdToTarget = relsParser.relationships
        }

        // Parse xl/workbook.xml for sheet name -> rId mapping
        let workbookXML = extractedDir.appendingPathComponent("xl/workbook.xml")
        guard FileManager.default.fileExists(atPath: workbookXML.path) else {
            return [:]
        }

        let parser = WorkbookXMLParser()
        let xmlParser = XMLParser(contentsOf: workbookXML)!
        xmlParser.delegate = parser
        xmlParser.parse()

        // Build path -> name map
        var result: [String: String] = [:]
        for sheet in parser.sheets {
            if let target = rIdToTarget[sheet.rId] {
                // CoreXLSX paths look like "xl/worksheets/sheet1.xml"
                // Relationship targets may be relative ("worksheets/...") or
                // package-absolute ("/xl/worksheets/...") after OOXML rewrite.
                let withoutLeadingSlash = target.hasPrefix("/")
                    ? String(target.drop(while: { $0 == "/" }))
                    : target
                let normalizedTarget = withoutLeadingSlash.hasPrefix("xl/")
                    ? withoutLeadingSlash
                    : "xl/\(withoutLeadingSlash)"
                result[normalizedTarget] = sheet.name
            }
        }
        return result
    }

    private func parseSharedStrings(from file: XLSXFile) throws -> [String] {
        guard let sharedStrings = try file.parseSharedStrings() else {
            return []
        }
        return sharedStrings.items.map { item in
            item.text ?? ""
        }
    }

    private func cellValue(_ cell: Cell, sharedStrings: [String]) -> String {
        if cell.type == .inlineStr {
            return cell.inlineString?.text ?? ""
        }
        guard let value = cell.value else { return "" }
        if let type = cell.type, type == .sharedString,
           let idx = Int(value), idx < sharedStrings.count {
            return sharedStrings[idx]
        }
        return value
    }

    // MARK: - Word (.docx)

    private func parseWord(url: URL) throws -> ParsedFile {
        let result = try parseOOXMLWithPython(url: url, fileType: "docx")
        return ParsedFile(
            fileName: url.lastPathComponent,
            fileType: .word,
            sheets: result.sheets,
            textContent: result.text
        )
    }

    // MARK: - PPT (.pptx)

    private func parsePPT(url: URL) throws -> ParsedFile {
        let result = try parseOOXMLWithPython(url: url, fileType: "pptx")
        return ParsedFile(
            fileName: url.lastPathComponent,
            fileType: .ppt,
            sheets: result.sheets,
            textContent: result.text
        )
    }

    // Common Python-based OOXML text and table extraction
    private struct OOXMLParseResult {
        let sheets: [SheetData]
        let text: String
    }

    private func parseOOXMLWithPython(url: URL, fileType: String) throws -> OOXMLParseResult {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let script = #"""
import json, sys, zipfile, tempfile, shutil, os
from xml.etree import ElementTree as ET

src = sys.argv[1]; ft = sys.argv[2]; dst = sys.argv[3]

tmpd = tempfile.mkdtemp()
with zipfile.ZipFile(src, 'r') as zf:
    zf.extractall(tmpd)

def get_text(elem):
    tag = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag
    if tag == "t" and elem.text:
        return elem.text
    return "".join(get_text(c) for c in elem)

def get_cell_text(cell):
    """Read this cell without folding a nested table into its parent cell."""
    parts = []
    def visit(elem):
        for child in elem:
            tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
            if tag == "tbl":
                continue
            if tag == "t" and child.text:
                parts.append(child.text)
            else:
                visit(child)
    visit(cell)
    return "".join(parts)

def direct_children(elem, wanted_tag):
    return [child for child in elem
            if (child.tag.split("}")[-1] if "}" in child.tag else child.tag) == wanted_tag]

def find_tables(elem, tables_list):
    """Recursively find all tables (including nested in cells)"""
    for child in elem:
        tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
        if tag == "tbl":
            rows = []
            for tr in direct_children(child, "tr"):
                cells = [get_cell_text(tc) for tc in direct_children(tr, "tc")]
                if cells:
                    rows.append(cells)
            if rows:
                tables_list.append(rows)
            # Continue below this table so nested tables become independent fields.
            find_tables(child, tables_list)
        else:
            find_tables(child, tables_list)

def orient_table(rows):
    """Return headers/records for row-oriented or transposed business tables."""
    label_names = {
        "时间", "地点", "上午", "下午", "供应商地址", "参与人员",
        "供应商名称", "型号", "特点", "官网链接", "天眼查信息",
        "降温方式", "备注", "姓名", "手机号", "邮箱",
    }
    candidates = rows
    if len(rows) >= 3 and sum(1 for value in rows[0] if value.strip()) == 1:
        candidates = rows[1:]
    if len(candidates) < 2:
        return rows[0], rows[1:]

    first_row_score = sum(1 for value in candidates[0] if value.strip() in label_names)
    first_column_score = sum(
        1 for row in candidates if row and row[0].strip() in label_names
    )
    if first_column_score > first_row_score:
        width = max(len(row) for row in candidates)
        headers = [row[0] if row else "" for row in candidates]
        records = [
            [row[column] if column < len(row) else "" for row in candidates]
            for column in range(1, width)
        ]
        return headers, records

    return candidates[0], candidates[1:]

def collect_all_text(elem, texts):
    """Collect all text from <t> elements, adding separators between paragraphs/cells"""
    for child in elem:
        tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
        if tag == "t" and child.text and child.text.strip():
            texts.append(child.text.strip())
        elif tag == "p":
            # Add newline between paragraphs
            pt = get_text(child).strip()
            if pt:
                texts.append(pt)
        else:
            collect_all_text(child, texts)

sheets = []
all_texts = []

if ft == "docx":
    doc_path = os.path.join(tmpd, "word", "document.xml")
    tree = ET.parse(doc_path)
    root = tree.getroot()
    body = None
    for el in root.iter():
        tag = el.tag.split("}")[-1] if "}" in el.tag else el.tag
        if tag == "body":
            body = el
            break
    if body is not None:
        all_tables = []
        find_tables(body, all_tables)
        for i, rows in enumerate(all_tables):
            if len(rows) >= 2:
                headers, records = orient_table(rows)
                sheets.append({"name": f"文档表格{i+1}", "headers": headers, "rows": records})
        collect_all_text(body, all_texts)

elif ft == "pptx":
    slides_dir = os.path.join(tmpd, "ppt", "slides")
    if os.path.isdir(slides_dir):
        table_idx = 0
        for fname in sorted(os.listdir(slides_dir)):
            if not fname.startswith("slide") or not fname.endswith(".xml"):
                continue
            tree = ET.parse(os.path.join(slides_dir, fname))
            root = tree.getroot()
            all_tables = []
            find_tables(root, all_tables)
            for rows in all_tables:
                if len(rows) >= 2:
                    headers, records = orient_table(rows)
                    sheets.append({"name": f"幻灯片表格{table_idx+1}", "headers": headers, "rows": records})
                    table_idx += 1
            collect_all_text(root, all_texts)

shutil.rmtree(tmpd)

result = {"sheets": sheets, "text": " ".join(all_texts)}
json.dump(result, open(dst, "w"))
"""#

        let status = try runPython(script: script, args: [url.path, fileType, jsonURL.path])
        guard status == 0 else {
            throw ParseError.invalidStructure("文档解析失败")
        }

        let jsonData = try Data(contentsOf: jsonURL)
        if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let text = dict["text"] as? String,
           let sheetsJSON = dict["sheets"] as? [[String: Any]] {
            let sheets: [SheetData] = sheetsJSON.compactMap { s in
                guard let name = s["name"] as? String,
                      let headers = s["headers"] as? [String],
                      let rows = s["rows"] as? [[String]] else { return nil }
                return SheetData(name: name, headers: headers, rows: rows)
            }
            return OOXMLParseResult(sheets: sheets, text: text)
        }
        throw ParseError.invalidStructure("文档解析结果异常")
    }

    // MARK: - Python helper

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
            fputs("Python parse error: \(errMsg)\n", stderr)
        }
        return process.terminationStatus
    }

    // MARK: - ZIP helper

    private func extractZip(url: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", url.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ParseError.invalidStructure("无法解压文件")
        }
        return tempDir
    }
}

// MARK: - Workbook XML Parser (for real sheet names)

private struct SheetEntry {
    let name: String
    let rId: String
}

private final class WorkbookXMLParser: NSObject, XMLParserDelegate {
    var sheets: [SheetEntry] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let isSheet = elementName == "sheet" || elementName.hasSuffix(":sheet")
        if isSheet, let name = attributes["name"] {
            let state = attributes["state"] ?? ""
            if state != "hidden" {
                let rId = attributes["r:id"] ?? attributes["id"] ?? ""
                sheets.append(SheetEntry(name: name, rId: rId))
            }
        }
    }
}

// MARK: - Relationship XML Parser

private final class RelsXMLParser: NSObject, XMLParserDelegate {
    var relationships: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "Relationship" || elementName.hasSuffix(":Relationship") {
            if let rId = attributes["Id"], let target = attributes["Target"] {
                relationships[rId] = target
            }
        }
    }
}
