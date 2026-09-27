import Foundation

final class SensitiveDetector: @unchecked Sendable {
    private let sampleSize = 20
    private let minMatchRatio = 0.3

    func analyze(_ parsedFile: ParsedFile) -> [FieldInfo] {
        var fields: [FieldInfo] = []

        for sheet in parsedFile.sheets {
            for (colIdx, header) in sheet.headers.enumerated() {
                let sampleValues = sampleColumn(rows: sheet.rows, columnIndex: colIdx)
                let displayName = header.isEmpty ? "列\(colIdx + 1)" : header
                var sensitiveTypes = RegexPatterns.detectSensitiveTypes(in: sampleValues)
                    .filter { $0 != .address }

                if isCompanyNameHeader(displayName), !sampleValues.isEmpty,
                   !sensitiveTypes.contains(.companyName) {
                    sensitiveTypes.append(.companyName)
                }
                if isPersonNameHeader(displayName),
                   sampleValues.contains(where: RegexPatterns.isChineseName),
                   !sensitiveTypes.contains(.chineseName) {
                    sensitiveTypes.append(.chineseName)
                }

                fields.append(FieldInfo(
                    name: displayName,
                    source: .table(sheetName: sheet.name),
                    sensitiveTypes: sensitiveTypes,
                    isSelected: !sensitiveTypes.isEmpty,
                    sampleValues: Array(sampleValues.prefix(5))
                ))
            }
        }

        let textFields = analyzeTextContent(parsedFile.textContent)
        fields.append(contentsOf: textFields)

        return fields
    }

    private func sampleColumn(rows: [[String]], columnIndex: Int) -> [String] {
        rows.prefix(sampleSize).compactMap { row in
            guard columnIndex < row.count else { return nil }
            let value = row[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    private func isCompanyNameHeader(_ header: String) -> Bool {
        let normalized = header.replacingOccurrences(of: " ", with: "")
        return ["供应商名称", "公司名称", "单位名称", "厂商名称", "客户名称"]
            .contains { normalized.contains($0) }
    }

    private func isPersonNameHeader(_ header: String) -> Bool {
        let normalized = header.replacingOccurrences(of: " ", with: "")
        return ["姓名", "参与人员", "同行人", "联系人", "负责人", "审批人", "经办人", "审核人"]
            .contains { normalized.contains($0) }
    }

    // Common non-name words that match surname patterns (days, locations, etc.)
    private static let nameBlocklist: Set<String> = [
        "周日","周一","周二","周三","周四","周五","周六","星期",
        "武汉","苏州","深圳","广州","杭州","南京","成都","西安",
        "时间","时空","时代","时期","时候","时间","气候","气温",
        "温度","高温","低温","方式","方案","方法","方向","方针",
        "成熟","成绩","成立","成功","成为","成本","成员",
        "市场","城市","工业","商业","农业","行业",
        "高铁","高速","高度","高层",
        "过程","进程","工程","流程",
        "供应商",
    ]

    private func analyzeTextContent(_ text: String) -> [FieldInfo] {
        guard !text.isEmpty else { return [] }

        var fields: [FieldInfo] = []
        let types = SensitiveType.allCases.filter { $0 != .address }

        for type in types {
            let pattern = RegexPatterns.pattern(for: type)
            guard !pattern.isEmpty,
                  let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, range: range)

            let minimumMatches = type == .companyName ? 1 : 2
            if matches.count >= minimumMatches {
                var allValues = matches.compactMap { match -> String? in
                    guard let r = Range(match.range, in: text) else { return nil }
                    return String(text[r])
                }

                // Chinese name: validate + split /-groups + filter blocklist
                if type == .chineseName {
                    var validNames = Set<String>()
                    for val in allValues {
                        // Split /-separated groups into individual names, validate each
                        let parts = val.components(separatedBy: "/")
                        for part in parts {
                            let trimmed = part.trimmingCharacters(in: .whitespaces)
                            if RegexPatterns.isChineseName(trimmed) && !Self.nameBlocklist.contains(trimmed) {
                                validNames.insert(trimmed)
                            }
                        }
                    }
                    guard validNames.count >= 2 else { continue }
                    allValues = Array(validNames)
                }

                let uniqueValues = Array(Set(allValues))

                fields.append(FieldInfo(
                    name: "正文-\(type.rawValue)",
                    source: .text,
                    sensitiveTypes: [type],
                    isSelected: true,
                    sampleValues: uniqueValues
                ))
            }
        }

        return fields
    }
}
