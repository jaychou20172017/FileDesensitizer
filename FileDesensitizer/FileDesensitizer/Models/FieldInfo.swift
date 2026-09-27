import Foundation

struct FieldInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let source: FieldSource
    var sensitiveTypes: [SensitiveType]
    var isSelected: Bool = false
    let sampleValues: [String]

    var displaySource: String {
        switch source {
        case .table(let sheetName):
            return "表格(\(sheetName))"
        case .text:
            return "正文"
        }
    }

    var isSensitive: Bool {
        !sensitiveTypes.isEmpty
    }
}

enum FieldSource: Hashable {
    case table(sheetName: String)
    case text
}

enum SensitiveType: String, CaseIterable, Hashable, Identifiable {
    case phone = "手机号"
    case idCard = "身份证"
    case email = "邮箱"
    case bankCard = "银行卡"
    case chineseName = "姓名"
    case companyName = "供应商名称"
    case address = "地址"
    case landline = "固话"

    var id: String { rawValue }
}
