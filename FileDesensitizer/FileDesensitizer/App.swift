import Foundation
import SwiftUI

@main
struct FileDesensitizerApp: App {
    init() {
#if DEBUG
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--integration-test"),
              CommandLine.arguments.indices.contains(flagIndex + 1) else {
            return
        }

        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1])
        do {
            let formatName = try IntegrationSelfTest.run(sourceURL: sourceURL)
            print("✓ \(formatName) 脱敏与恢复端到端测试通过")
            fflush(stdout)
            exit(EXIT_SUCCESS)
        } catch {
            fputs("✗ 端到端测试失败：\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 640)
    }
}

#if DEBUG
private enum IntegrationSelfTest {
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run(sourceURL: URL) throws -> String {
        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FileDesensitizerIntegration-\(UUID().uuidString)")
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let keepOutput = ProcessInfo.processInfo.environment["KEEP_INTEGRATION_OUTPUT"] == "1"
        defer {
            if keepOutput {
                print("自检临时目录：\(outputDirectory.path)")
            } else {
                try? fileManager.removeItem(at: outputDirectory)
            }
        }

        let parser = FileParserService()
        let original = try parser.parse(url: sourceURL)
        if sourceURL.lastPathComponent == "excel_regression.xlsx" {
            try validateExcelRegressionFixture(original)
        }

        let analyzedFields = SensitiveDetector().analyze(original)
        let selectedFields = analyzedFields.filter(\.isSensitive)
        guard !selectedFields.isEmpty else {
            throw Failure(message: "测试文件未检测到敏感字段")
        }
        let analysisSummary = analyzedFields.map {
            let types = $0.sensitiveTypes.map(\.rawValue).joined(separator: "/")
            return "\($0.name)[\($0.sampleValues.count):\(types)]"
        }.joined(separator: ", ")
        print("自检字段分析：\(analysisSummary)")
        let fieldSummary = selectedFields.map {
            "\($0.displaySource):\($0.name)(\($0.sampleValues.count))"
        }.joined(separator: ", ")
        print("自检选中字段：\(fieldSummary)")

        let maskedResult = try DesensitizeService().desensitize(
            parsedFile: original,
            originalFileURL: sourceURL,
            selectedFields: selectedFields,
            outputDir: outputDirectory
        )
        let masksByOriginal = Dictionary(grouping: maskedResult.mappings, by: \.originalValue)
            .mapValues { Set($0.map(\.maskedValue)) }
        guard masksByOriginal.values.allSatisfy({ $0.count == 1 }) else {
            throw Failure(message: "同一原始值生成了多个脱敏值")
        }
        guard let maskedURL = maskedResult.outputFileURL,
              let mappingURL = maskedResult.mappingFileURL,
              fileManager.fileExists(atPath: maskedURL.path),
              fileManager.fileExists(atPath: mappingURL.path),
              mappingURL.pathExtension.lowercased() == "xlsx" else {
            throw Failure(message: "未生成完整的脱敏文件和 XLSX 映射表")
        }

        let masked = try parser.parse(url: maskedURL)
        let originalComparison = comparisonData(original, selectedFields: selectedFields)
        guard comparisonData(masked, selectedFields: selectedFields) != originalComparison else {
            throw Failure(message: "脱敏文件的内容未发生变化")
        }
        if original.fileType == .excel {
            try validateAllSelectedCellsChanged(
                original: original,
                masked: masked,
                selectedFields: selectedFields
            )
        }

        let recoveredResult = try RecoverService().recover(
            maskedFileURL: maskedURL,
            mappingTableURL: mappingURL,
            outputDir: outputDirectory
        )
        guard let recoveredURL = recoveredResult.outputFileURL else {
            throw Failure(message: "未生成恢复文件")
        }

        let recovered = try parser.parse(url: recoveredURL)
        guard comparisonData(recovered, selectedFields: selectedFields) == originalComparison else {
            throw Failure(message: "恢复后的文档内容与原文件不一致")
        }
        return original.fileType.displayName
    }

    private static func validateExcelRegressionFixture(_ file: ParsedFile) throws {
        guard file.sheets.map(\.name) == ["说明", "人员调整"],
              let sheet = file.sheets.last,
              sheet.headers.indices.contains(9),
              sheet.headers[6] == "原姓名",
              sheet.headers[7] == "新姓名",
              sheet.headers[9] == "审批人",
              sheet.rows.count == 3,
              sheet.rows[1][7].isEmpty,
              sheet.rows.map({ $0[9] }) == ["张三", "王芳", "张三"] else {
            throw Failure(message: "Excel 稀疏列、Sheet 顺序或公式缓存回归样例解析失败")
        }
    }

    private static func validateAllSelectedCellsChanged(
        original: ParsedFile,
        masked: ParsedFile,
        selectedFields: [FieldInfo]
    ) throws {
        for field in selectedFields {
            guard case .table(let sheetName) = field.source,
                  let originalSheet = original.sheets.first(where: { $0.name == sheetName }),
                  let maskedSheet = masked.sheets.first(where: { $0.name == sheetName }),
                  let originalColumn = originalSheet.headers.firstIndex(of: field.name),
                  let maskedColumn = maskedSheet.headers.firstIndex(of: field.name) else {
                continue
            }

            for rowIndex in originalSheet.rows.indices {
                let originalRow = originalSheet.rows[rowIndex]
                guard originalColumn < originalRow.count else { continue }
                let originalValue = originalRow[originalColumn]
                guard !originalValue.isEmpty else { continue }
                guard rowIndex < maskedSheet.rows.count,
                      maskedColumn < maskedSheet.rows[rowIndex].count,
                      maskedSheet.rows[rowIndex][maskedColumn] != originalValue else {
                    throw Failure(message: "Excel 字段 \(field.name) 存在未脱敏的非空单元格")
                }
            }
        }
    }

    private static func comparisonData(_ file: ParsedFile, selectedFields: [FieldInfo]) -> [String] {
        return selectedFields.flatMap { field -> [String] in
            guard case .table(let sheetName) = field.source,
                  let sheet = file.sheets.first(where: { $0.name == sheetName }),
                  let columnIndex = sheet.headers.firstIndex(of: field.name) else {
                return []
            }
            return [sheetName, field.name] + sheet.rows.map { row in
                columnIndex < row.count ? row[columnIndex] : ""
            }
        }
    }

}
#endif
