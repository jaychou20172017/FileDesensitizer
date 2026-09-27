import Foundation

struct MappingEntry: Identifiable, Hashable {
    let id = UUID()
    let fieldName: String
    let originalValue: String
    let maskedValue: String
}
