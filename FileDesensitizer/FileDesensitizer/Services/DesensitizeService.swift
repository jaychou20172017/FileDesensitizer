import Foundation
import CryptoKit

final class DesensitizeService: @unchecked Sendable {
    private let salt = "FD_v1_salt"

    func desensitize(parsedFile: ParsedFile, originalFileURL: URL?,
                     selectedFields: [FieldInfo], outputDir: URL) throws -> ProcessingResult {
        var allMappings: [MappingEntry] = []
        var seen: Set<String> = []
        var maskByOriginal: [String: String] = [:]
        var originalByMask: [String: String] = [:]
        let allRealValues = Set(selectedFields.flatMap {
            collectValues(for: $0, parsedFile: parsedFile).filter { !$0.isEmpty }
        })

        for field in selectedFields {
            let values = collectValues(for: field, parsedFile: parsedFile)
            for value in values where !value.isEmpty {
                let dedupKey = "\(field.name)|\(value)"
                guard !seen.contains(dedupKey) else { continue }
                seen.insert(dedupKey)

                let masked: String
                if let existing = maskByOriginal[value] {
                    masked = existing
                } else {
                    var candidate = generateMaskedValue(
                        for: value,
                        seed: value,
                        preferredType: field.sensitiveTypes.first
                    )
                    var retry = 0
                    while (candidate == value || allRealValues.contains(candidate)
                           || (originalByMask[candidate] != nil && originalByMask[candidate] != value)),
                          retry < 100 {
                        retry += 1
                        candidate = generateMaskedValue(
                            for: value,
                            seed: "\(value)_r\(retry)",
                            preferredType: field.sensitiveTypes.first
                        )
                    }
                    masked = candidate
                    maskByOriginal[value] = masked
                    originalByMask[masked] = value
                }
                allMappings.append(MappingEntry(
                    fieldName: field.name,
                    originalValue: value,
                    maskedValue: masked
                ))
            }
        }

        let initialMappings = allMappings.sorted { ($0.fieldName, $0.originalValue) < ($1.fieldName, $1.originalValue) }

        let outputURL = outputDir.appendingPathComponent(
            FileFormatUtils.desensitizedFileName(for: URL(fileURLWithPath: parsedFile.fileName))
        )
        let mappingURL = outputDir.appendingPathComponent(
            FileFormatUtils.mappingFileName(for: URL(fileURLWithPath: parsedFile.fileName))
        )

        let finalMappings: [MappingEntry]
        switch parsedFile.fileType {
        case .excel:
            finalMappings = try writeExcelOutput(originalFileURL: originalFileURL, parsedFile: parsedFile,
                                 selectedFields: selectedFields,
                                 mappings: initialMappings, outputURL: outputURL)
        case .word, .ppt:
            throw ParseError.unsupportedFormat
        case .unknown:
            throw ParseError.unsupportedFormat
        }

        try writeMappingTable(mappings: finalMappings, outputURL: mappingURL)

        return ProcessingResult(
            fileName: parsedFile.fileName,
            totalFields: selectedFields.count,
            totalRows: finalMappings.count,
            mappings: finalMappings,
            outputFileURL: outputURL,
            mappingFileURL: mappingURL
        )
    }

    // MARK: - Mask value generation

    private func generateMaskedValue(for original: String, seed: String,
                                     preferredType: SensitiveType? = nil) -> String {
        let hash = SHA256.hash(data: Data((seed + salt).utf8))
        let bytes = Array(hash)

        if let type = preferredType ?? detectPrimaryType(original) {
            return formatPreservingMask(original: original, type: type, bytes: bytes)
        }
        return "MASKED_\(String(bytes[0..<6].map { String(format: "%02X", $0) }.joined().prefix(8)))"
    }

    private func detectPrimaryType(_ value: String) -> SensitiveType? {
        RegexPatterns.detectSensitiveTypes(in: value).first
    }

    private func formatPreservingMask(original: String, type: SensitiveType, bytes: [UInt8]) -> String {
        switch type {
        case .phone:
            let seedVal = bytes[0..<4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let suffixNum = Int(abs(Int64(seedVal)) % 99_999_999)
            let suffix = String(format: "%08d", suffixNum)
            let prefixNum = Int(bytes[0]) % 8
            let prefixes = ["39","58","68","78","88","98","38","59"]
            return "1\(prefixes[prefixNum])\(suffix)"

        case .idCard:
            let area = ["110101","310101","440103","320102","330102"].randomElement(using: bytes)
            let birth = String(format: "%04d%02d%02d",
                1960 + Int(bytes[1]) % 50,
                1 + Int(bytes[2]) % 12,
                1 + Int(bytes[3]) % 28)
            let suffix = String(format: "%04d", Int(bytes[4..<8].reduce(0) { UInt64($0) << 8 | UInt64($1) }) % 10000)
            return "\(area)\(birth)\(suffix)"

        case .email:
            let names = ["user", "info", "admin", "service", "mail"]
            let domains = ["example.com", "domain.cn", "test.org", "mail.cn"]
            let nameIdx = Int(bytes[0]) % names.count
            let domainIdx = Int(bytes[1]) % domains.count
            let suffix = String(format: "%04d", Int(bytes[2..<4].reduce(0) { UInt16($0) << 8 | UInt16($1) }) % 10000)
            return "\(names[nameIdx])\(suffix)@\(domains[domainIdx])"

        case .bankCard:
            let digits = (0..<original.count).map { i in "\(bytes[i % bytes.count] % 10)" }.joined()
            return digits

        case .chineseName:
            let surnames: [String] = [
                "张","王","李","赵","陈","杨","黄","周","吴","徐","孙","马","胡","朱","郭","何","罗","高","林","郑",
                "梁","谢","唐","许","邓","韩","冯","曹","彭","曾","肖","田","董","潘","袁","蔡","蒋","余","于","杜",
                "叶","程","苏","魏","吕","丁","任","卢","姚","沈","钟","姜","崔","谭","陆","范","汪","廖","石","金",
                "韦","贾","夏","付","方","白","邹","孟","熊","秦","邱","江","尹","薛","闫","段","雷","侯","龙","黎",
                "史","陶","贺","毛","郝","顾","龚","邵","万","钱","严","覃","武","戴","莫","孔","向","汤","温","康"
            ]
            let nameChars: [String] = [
                "明","华","伟","芳","敏","静","丽","强","磊","洋","勇","艳","涛","军","杰","文","波","斌","霞",
                "平","刚","桂","英","辉","玲","秀","峰","燕","红","志","健","宁","欣","玉","兰","海","亮","飞",
                "超","雪","晶","梅","娟","威","鹏","蕾","睿","颖","林","佳","鑫","博","帅","阳","悦","成","云",
                "庆","新","龙","洪","春","义","喜","美","瑞","金","东","长","江","凤","丹","莉","亚","秋","良"
            ]
            let surnameCount = UInt32(surnames.count)
            let nameCharCount = UInt32(nameChars.count)
            let s = surnames[Int(UInt32(bytes[0]) % surnameCount)]
            let c1 = nameChars[Int(UInt32(bytes[4]) % nameCharCount)]
            let c2 = nameChars[Int(UInt32(bytes[8]) % nameCharCount)]
            let c3 = nameChars[Int((UInt32(bytes[12]) << 8 | UInt32(bytes[13])) % nameCharCount)]
            // 50/50 mix of 2-char and 3-char given names for variety
            let given = (bytes[1] % 2 == 0) ? "\(c1)\(c2)" : "\(c1)\(c2)\(c3)"
            return "\(s)\(given)"

        case .companyName:
            let suffixes = ["股份有限公司", "有限责任公司", "有限公司"]
            let suffix = suffixes.first(where: original.hasSuffix) ?? "有限公司"
            let identifier = bytes.prefix(4)
                .map { String(format: "%02X", $0) }
                .joined()
            return "供应商_\(identifier)\(suffix)"

        case .address:
            let cities = ["北京市朝阳区","上海市浦东新区","广州市天河区","深圳市南山区","杭州市西湖区"]
            let streetNum = Int(bytes[0..<4].reduce(0) { UInt32($0) << 8 | UInt32($1) }) % 999
            return "\(cities[Int(bytes[0]) % cities.count])某路\(streetNum)号"

        case .landline:
            let codes = ["010","021","020","0755","0571","028","025","027"]
            let code = codes[Int(bytes[0]) % codes.count]
            let num = String(format: "%08d", Int(bytes[1..<5].reduce(0) { UInt32($0) << 8 | UInt32($1) }) % 100_000_000)
            return "\(code)-\(num)"
        }
    }

    // MARK: - Value collection

    private func collectValues(for field: FieldInfo, parsedFile: ParsedFile) -> [String] {
        let rawValues: [String]
        switch field.source {
        case .table(let sheetName):
            guard let sheet = parsedFile.sheets.first(where: { $0.name == sheetName }) else { return [] }
            let colIdx = sheet.headers.firstIndex(of: field.name) ?? -1
            guard colIdx >= 0 else { return [] }
            rawValues = sheet.rows.compactMap { row in colIdx < row.count ? row[colIdx] : nil }
        case .text:
            rawValues = field.sampleValues
        }

        if field.sensitiveTypes.contains(.chineseName) {
            return rawValues.flatMap { value in
                value.components(separatedBy: "/")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter(RegexPatterns.isChineseName)
            }
        }

        if field.sensitiveTypes.contains(.companyName) {
            let pattern = RegexPatterns.pattern(for: .companyName)
            let regex = try? NSRegularExpression(pattern: pattern)
            return rawValues.flatMap { value -> [String] in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "\\", trimmed != "无" else { return [] }
                guard let regex else { return [trimmed] }
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                let matches = regex.matches(in: trimmed, range: range).compactMap { match -> String? in
                    guard let matchRange = Range(match.range, in: trimmed) else { return nil }
                    return String(trimmed[matchRange])
                }
                return matches.isEmpty ? [trimmed] : matches
            }
        }

        return rawValues
    }

    // MARK: - Output writers

    private func writeExcelOutput(originalFileURL: URL?, parsedFile: ParsedFile,
                                   selectedFields: [FieldInfo],
                                   mappings: [MappingEntry], outputURL: URL) throws -> [MappingEntry] {
        guard let srcURL = originalFileURL else {
            throw ParseError.invalidStructure("找不到原始文件")
        }

        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let outJSONURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_out.json")
        defer {
            try? FileManager.default.removeItem(at: jsonURL)
            try? FileManager.default.removeItem(at: outJSONURL)
        }

        // Use real sheet names. CoreXLSX worksheet-path order is not guaranteed to
        // match the display order used by openpyxl.
        let fieldData: [[String: Any]] = selectedFields.compactMap { field in
            guard case .table(let sheetName) = field.source else { return nil }
            return ["header": field.name, "sheetName": sheetName]
        }
        let mappingData: [[String: String]] = mappings.map {
            ["fieldName": $0.fieldName, "originalValue": $0.originalValue, "maskedValue": $0.maskedValue]
        }
        let payload: [String: Any] = ["fields": fieldData, "mappings": mappingData]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        try jsonData.write(to: jsonURL)
        let script = #"""
import openpyxl, json, sys, hashlib
src = sys.argv[1]; jp = sys.argv[2]; dst = sys.argv[3]; out_json = sys.argv[4]
with open(jp) as f:
    data = json.load(f)
wb = openpyxl.load_workbook(src, data_only=False)
cached_wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
mappings = data["mappings"]
fields = data["fields"]
field_locations = {}
for field in fields:
    sn = field.get("sheetName")
    if sn not in wb.sheetnames:
        continue
    ws = wb[sn]
    header = str(field["header"])
    for c in range(1, ws.max_column + 1):
        if str(ws.cell(row=1, column=c).value or '') == header:
            field_locations.setdefault(header, []).append((sn, c))
            break
# Collect all real values per field for collision detection
real_values = {}
for header, locations in field_locations.items():
    vals = set()
    for sn, c in locations:
        ws = wb[sn]
        cached_ws = cached_wb[sn]
        for r in range(2, ws.max_row + 1):
            cell = ws.cell(row=r, column=c)
            cv = cached_ws.cell(row=r, column=c).value if cell.data_type == "f" else cell.value
            if cv is not None:
                vals.add(str(cv))
    real_values[header] = vals
# Collision fix: adjust masked values that collide with real values in the same column
collisions_fixed = 0
for m in mappings:
    fn = m["fieldName"]
    orig = str(m["originalValue"])
    masked = m["maskedValue"]
    rv = real_values.get(fn, set())
    if masked in rv and masked != orig:
        base = masked
        attempt = 0
        while masked in rv and masked != orig and attempt < 20:
            attempt += 1
            suffix = hashlib.sha256(f"{base}_{attempt}".encode()).hexdigest()[:4]
            masked = f"{base}_{suffix}"
        if masked != m["maskedValue"]:
            m["maskedValue"] = masked
            collisions_fixed += 1
# Build lookup
lookup = {}
for m in mappings:
    fn = m["fieldName"]
    for sn, col in field_locations.get(fn, []):
        lookup[(sn, col, str(m["originalValue"]))] = m["maskedValue"]
cnt = 0
for (sn, col, orig), masked in lookup.items():
    ws = wb[sn]
    cached_ws = cached_wb[sn]
    for r in range(2, ws.max_row + 1):
        cell = ws.cell(row=r, column=col)
        comparison_value = cached_ws.cell(row=r, column=col).value if cell.data_type == "f" else cell.value
        if comparison_value is not None and str(comparison_value) == orig:
            cell.value = masked
            cnt += 1
if mappings and cnt == 0:
    mapped_values = {str(m["originalValue"]) for m in mappings}
    target_hits = 0
    for locations in field_locations.values():
        for sn, col in locations:
            ws = wb[sn]
            cached_ws = cached_wb[sn]
            for r in range(2, ws.max_row + 1):
                cell = ws.cell(row=r, column=col)
                value = cached_ws.cell(row=r, column=col).value if cell.data_type == "f" else cell.value
                if value is not None and str(value) in mapped_values:
                    target_hits += 1
    workbook_hits = 0
    for sn in wb.sheetnames:
        ws = wb[sn]
        cached_ws = cached_wb[sn]
        for row in ws.iter_rows():
            for cell in row:
                value = cached_ws.cell(row=cell.row, column=cell.column).value if cell.data_type == "f" else cell.value
                if value is not None and str(value) in mapped_values:
                    workbook_hits += 1
    print(f"所选字段中未找到可替换的原始值; fields={len(field_locations)} lookup={len(lookup)} targetHits={target_hits} workbookHits={workbook_hits}", file=sys.stderr)
    sys.exit(3)
wb.save(dst)
json.dump(mappings, open(out_json, 'w'))
print(f"MASKED:{cnt} FIXED:{collisions_fixed}")
"""#

        let status = try runPython(script: script, args: [srcURL.path, jsonURL.path, outputURL.path, outJSONURL.path])
        if status == 3 {
            throw ParseError.invalidStructure("所选字段没有匹配到可脱敏的单元格，请重新检查 Sheet 和字段选择")
        }
        guard status == 0 else {
            throw ParseError.invalidStructure("Excel 写入失败")
        }

        // Read back corrected mappings from Python
        let outData = try Data(contentsOf: outJSONURL)
        if let corrected = try JSONSerialization.jsonObject(with: outData) as? [[String: String]] {
            var result: [MappingEntry] = []
            for m in corrected {
                if let fn = m["fieldName"], let ov = m["originalValue"], let mv = m["maskedValue"] {
                    result.append(MappingEntry(fieldName: fn, originalValue: ov, maskedValue: mv))
                }
            }
            return result.sorted { ($0.fieldName, $0.originalValue) < ($1.fieldName, $1.originalValue) }
        }
        return mappings
    }

    private func writeOOXMLOutput(originalFileURL: URL?, parsedFile: ParsedFile,
                                   selectedFields: [FieldInfo],
                                   mappings: [MappingEntry], outputURL: URL) throws -> [MappingEntry] {
        guard let srcURL = originalFileURL else {
            throw ParseError.invalidStructure("找不到原始文件")
        }

        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let outJSONURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_out.json")
        defer {
            try? FileManager.default.removeItem(at: jsonURL)
            try? FileManager.default.removeItem(at: outJSONURL)
        }

        let sheetsInOrder = parsedFile.sheets.map { $0.name }
        let fieldData: [[String: Any]] = selectedFields.map { field in
            var dict: [String: Any] = ["header": field.name]
            switch field.source {
            case .table(let sheetName):
                dict["source"] = "table"
                dict["sheetIndex"] = sheetsInOrder.firstIndex(of: sheetName) ?? 0
            case .text:
                dict["source"] = "text"
            }
            return dict
        }
        let mappingData: [[String: String]] = mappings.map {
            ["fieldName": $0.fieldName, "originalValue": $0.originalValue, "maskedValue": $0.maskedValue]
        }
        let payload: [String: Any] = ["fields": fieldData, "mappings": mappingData]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        try jsonData.write(to: jsonURL)

        let ext = srcURL.pathExtension.lowercased()
        let script = #"""
import json, sys, os, shutil, zipfile, tempfile, hashlib, re
from xml.etree import ElementTree as ET
from xml.sax.saxutils import quoteattr

src = sys.argv[1]; jp = sys.argv[2]; dst = sys.argv[3]; out_json = sys.argv[4]
ftype = sys.argv[5]

with open(jp) as f:
    data = json.load(f)
mappings = data["mappings"]
fields = data["fields"]

# Extract ZIP
tmpd = tempfile.mkdtemp()
with zipfile.ZipFile(src, 'r') as zf:
    zf.extractall(tmpd)

# Namespaces
NS_W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main"

def parse_preserving_namespaces(path):
    namespaces = []
    seen = set()
    for _, item in ET.iterparse(path, events=("start-ns",)):
        prefix, uri = item
        prefix = prefix or ""
        if prefix not in seen:
            namespaces.append((prefix, uri))
            seen.add(prefix)
            ET.register_namespace(prefix, uri)
    return ET.parse(path), namespaces

def write_preserving_namespaces(tree, path, namespaces):
    """Keep declarations referenced by mc:Ignorable and similar attributes."""
    data = ET.tostring(tree.getroot(), encoding="UTF-8", xml_declaration=True)
    declaration_end = data.find(b"?>")
    root_start = data.find(b"<", declaration_end + 2)
    root_end = data.find(b">", root_start)
    root_opening = data[root_start:root_end]
    declared = {
        (match.group(1) or b"").decode("utf-8")
        for match in re.finditer(rb"\sxmlns(?::([A-Za-z0-9_.-]+))?=", root_opening)
    }
    additions = []
    for prefix, uri in namespaces:
        if prefix not in declared:
            name = "xmlns" if not prefix else f"xmlns:{prefix}"
            additions.append(f" {name}={quoteattr(uri)}".encode("utf-8"))
    if additions:
        data = data[:root_end] + b"".join(additions) + data[root_end:]
    with open(path, "wb") as output:
        output.write(data)

def itertext(elem):
    """Collect all text from <w:t> or <a:t> descendants"""
    texts = []
    for el in elem.iter():
        tag = el.tag.split("}")[-1] if "}" in el.tag else el.tag
        if tag == "t" and el.text:
            texts.append((el, el.text))
    return texts

def set_cell_text(cell_elem, new_text, ns):
    """Replace text in a table cell (docx tc or pptx tc)"""
    replaced = False
    for el in cell_elem.iter():
        tag = el.tag.split("}")[-1] if "}" in el.tag else el.tag
        if tag == "t":
            el.text = new_text if not replaced else ""
            replaced = True

def get_cell_text(cell_elem):
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
    visit(cell_elem)
    return "".join(parts)

def direct_children(elem, wanted_tag):
    return [child for child in elem
            if (child.tag.split("}")[-1] if "}" in child.tag else child.tag) == wanted_tag]

def table_rows(table):
    return direct_children(table, "tr")

def row_cells(row):
    return direct_children(row, "tc")

def fix_text_elements(root, lookup):
    """Replace text in all <t> elements matching lookup values (exact or substring)"""
    count = 0
    # Sort by length descending to avoid shorter matches corrupting longer ones
    sorted_items = sorted(lookup.items(), key=lambda x: len(x[0]), reverse=True)
    for elem in root.iter():
        tag = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag
        if tag == "t" and elem.text:
            for orig, masked in sorted_items:
                if orig in elem.text:
                    elem.text = elem.text.replace(orig, masked)
                    count += 1
    return count

def replace_cell_values(cell, lookup, ns):
    """Replace mapped substrings while preserving separators and notes."""
    original = get_cell_text(cell)
    updated = original
    count = 0
    for source, masked in sorted(lookup.items(), key=lambda item: len(item[0]), reverse=True):
        occurrences = updated.count(source)
        if occurrences:
            updated = updated.replace(source, masked)
            count += occurrences
    if updated != original:
        set_cell_text(cell, updated, ns)
    return count

if ftype in ("docx", "doc"):
    doc_path = os.path.join(tmpd, "word", "document.xml")
    tree, document_namespaces = parse_preserving_namespaces(doc_path)
    root = tree.getroot()

    # Keep only tables that the parser exposes as sheets, in the same order.
    tbl_elems = []
    for el in root.iter():
        tag = el.tag.split("}")[-1] if "}" in el.tag else el.tag
        if tag == "tbl" and len(table_rows(el)) >= 2:
            tbl_elems.append(el)

    # Build lookup per field
    table_lookups = {}  # field_name -> {orig: masked}
    text_lookup = {}    # orig -> masked
    for m in mappings:
        fn = m["fieldName"]
        fi = next((f for f in fields if f["header"] == fn), None)
        if fi and fi.get("source") == "table":
            if fn not in table_lookups:
                table_lookups[fn] = {}
            table_lookups[fn][str(m["originalValue"])] = m["maskedValue"]
        else:
            text_lookup[str(m["originalValue"])] = m["maskedValue"]

    # Process table fields
    total_masked = 0
    for fi in fields:
        fn = fi["header"]
        if fi.get("source") == "table" and fn in table_lookups:
            tbl_idx = fi.get("sheetIndex", 0)
            if tbl_idx < len(tbl_elems):
                tbl = tbl_elems[tbl_idx]
                rows = table_rows(tbl)
                if rows:
                    # Find header row and column index
                    header_cells = [get_cell_text(cell) for cell in row_cells(rows[0])]
                    col_idx = None
                    for i, h in enumerate(header_cells):
                        if h.strip() == fn:
                            col_idx = i
                            break
                    if col_idx is not None:
                        lup = table_lookups[fn]
                        for row in rows[1:]:
                            cells = row_cells(row)
                            if col_idx < len(cells):
                                total_masked += replace_cell_values(cells[col_idx], lup, NS_W)
                    else:
                        # Transposed table: field names are in the first column
                        # and each following cell is one supplier/person record.
                        lup = table_lookups[fn]
                        for row in rows:
                            cells = row_cells(row)
                            if cells and get_cell_text(cells[0]).strip() == fn:
                                for cell in cells[1:]:
                                    total_masked += replace_cell_values(cell, lup, NS_W)

    # Process text fields
    text_count = 0
    if text_lookup:
        text_count = fix_text_elements(root, text_lookup)
        total_masked += text_count

    write_preserving_namespaces(tree, doc_path, document_namespaces)

elif ftype in ("pptx", "ppt"):
    slides_dir = os.path.join(tmpd, "ppt", "slides")
    # Build lookup
    table_lookups = {}
    text_lookup = {}
    for m in mappings:
        fn = m["fieldName"]
        fi = next((f for f in fields if f["header"] == fn), None)
        if fi and fi.get("source") == "table":
            if fn not in table_lookups:
                table_lookups[fn] = {}
            table_lookups[fn][str(m["originalValue"])] = m["maskedValue"]
        else:
            text_lookup[str(m["originalValue"])] = m["maskedValue"]

    total_masked = 0
    tbl_count = 0
    if os.path.isdir(slides_dir):
        for fname in sorted(os.listdir(slides_dir)):
            if not fname.startswith("slide") or not fname.endswith(".xml"):
                continue
            spath = os.path.join(slides_dir, fname)
            tree, slide_namespaces = parse_preserving_namespaces(spath)
            root = tree.getroot()

            # Find tables in this slide
            tbl_elems = []
            for el in root.iter():
                tag = el.tag.split("}")[-1] if "}" in el.tag else el.tag
                if tag == "tbl":
                    tbl_elems.append(el)

            for tbl in tbl_elems:
                rows = table_rows(tbl)
                if len(rows) < 2:
                    continue
                for fi in fields:
                    fn = fi["header"]
                    if fi.get("source") == "table" and fi.get("sheetIndex", 0) == tbl_count and fn in table_lookups:
                        if rows:
                            header_cells = [get_cell_text(cell) for cell in row_cells(rows[0])]
                            col_idx = None
                            for i, h in enumerate(header_cells):
                                if h.strip() == fn:
                                    col_idx = i
                                    break
                            if col_idx is not None:
                                lup = table_lookups[fn]
                                for row in rows[1:]:
                                    cells = row_cells(row)
                                    if col_idx < len(cells):
                                        total_masked += replace_cell_values(cells[col_idx], lup, NS_A)
                            else:
                                lup = table_lookups[fn]
                                for row in rows:
                                    cells = row_cells(row)
                                    if cells and get_cell_text(cells[0]).strip() == fn:
                                        for cell in cells[1:]:
                                            total_masked += replace_cell_values(cell, lup, NS_A)
                tbl_count += 1

            # Process text fields
            if text_lookup:
                total_masked += fix_text_elements(root, text_lookup)

            write_preserving_namespaces(tree, spath, slide_namespaces)

# Re-zip
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zout:
    for dirpath, dirnames, filenames in os.walk(tmpd):
        for fn in filenames:
            fpath = os.path.join(dirpath, fn)
            aname = os.path.relpath(fpath, tmpd)
            zout.write(fpath, aname)

shutil.rmtree(tmpd)
json.dump(mappings, open(out_json, 'w'))
print(f"MASKED:{total_masked} FIXED:0")
"""#

        let status = try runPython(script: script, args: [srcURL.path, jsonURL.path, outputURL.path, outJSONURL.path, ext])
        guard status == 0 else {
            throw ParseError.invalidStructure("文档写入失败")
        }

        let outData = try Data(contentsOf: outJSONURL)
        if let corrected = try JSONSerialization.jsonObject(with: outData) as? [[String: String]] {
            var result: [MappingEntry] = []
            for m in corrected {
                if let fn = m["fieldName"], let ov = m["originalValue"], let mv = m["maskedValue"] {
                    result.append(MappingEntry(fieldName: fn, originalValue: ov, maskedValue: mv))
                }
            }
            return result.sorted { ($0.fieldName, $0.originalValue) < ($1.fieldName, $1.originalValue) }
        }
        return mappings
    }

    private func writeMappingTable(mappings: [MappingEntry], outputURL: URL) throws {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let rows = mappings.map {
            [$0.fieldName, $0.originalValue, $0.maskedValue]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: rows, options: [])
        try jsonData.write(to: jsonURL)

        let script = #"""
import json, sys, openpyxl
from openpyxl.styles import Font, PatternFill

src = sys.argv[1]; dst = sys.argv[2]
with open(src) as f:
    rows = json.load(f)

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "脱敏映射表"
ws.append(["字段名", "原始值", "脱敏值"])
for row in rows:
    ws.append(row)

header_fill = PatternFill("solid", fgColor="E8F0FE")
for cell in ws[1]:
    cell.font = Font(bold=True)
    cell.fill = header_fill
ws.freeze_panes = "A2"
ws.auto_filter.ref = ws.dimensions
ws.column_dimensions["A"].width = 24
ws.column_dimensions["B"].width = 36
ws.column_dimensions["C"].width = 36
wb.save(dst)
"""#

        let status = try runPython(script: script, args: [jsonURL.path, outputURL.path])
        guard status == 0 else {
            throw ParseError.invalidStructure("映射表写入失败")
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
            fputs("Python error: \(errMsg)\n", stderr)
        }
        return process.terminationStatus
    }
}

extension Array {
    func randomElement(using bytes: [UInt8]) -> Element {
        let idx = Int(bytes[0]) % count
        return self[idx]
    }
}
