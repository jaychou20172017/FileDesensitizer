import Foundation

struct ProcessingResult {
    let fileName: String
    let totalFields: Int
    let totalRows: Int
    let mappings: [MappingEntry]
    let outputFileURL: URL?
    let mappingFileURL: URL?

    var summary: String {
        "已处理 \(totalFields) 个字段，共 \(totalRows) 行数据"
    }
}
