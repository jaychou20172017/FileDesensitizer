import Foundation
import UniformTypeIdentifiers

enum FileFormatUtils {
    static let maximumFileSizeBytes: Int64 = 100 * 1024 * 1024

    enum FileType {
        case excel, word, ppt, unknown

        var displayName: String {
            switch self {
            case .excel: return "Excel"
            case .word: return "Word"
            case .ppt: return "PPT"
            case .unknown: return "未知"
            }
        }
    }

    static func detectFileType(from url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "xlsx", "xls": return .excel
        case "docx", "doc": return .word
        case "pptx", "ppt": return .ppt
        default: return .unknown
        }
    }

    static func isSupported(url: URL) -> Bool {
        url.pathExtension.lowercased() == "xlsx"
    }

    static func isLegacyOfficeFormat(url: URL) -> Bool {
        url.pathExtension.lowercased() == "xls"
    }

    static func modernExtension(forLegacyURL url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "xls": return "xlsx"
        default: return nil
        }
    }

    static func supportedExtensions() -> [String] {
        ["xlsx"]
    }

    static func displayFileSize(_ url: URL) -> String {
        guard let size = fileSizeInBytes(at: url) else {
            return "未知"
        }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }

    static func fileSizeInBytes(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attrs[.size] as? NSNumber else {
            return nil
        }
        return number.int64Value
    }

    static func isWithinFileSizeLimit(_ size: Int64) -> Bool {
        size >= 0 && size <= maximumFileSizeBytes
    }

    static func desensitizedFileName(for original: URL) -> String {
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        return "\(base)_脱敏.\(ext)"
    }

    static func mappingFileName(for original: URL) -> String {
        let base = original.deletingPathExtension().lastPathComponent
        return "\(base)_脱敏映射表.xlsx"
    }

    static func recoveredFileName(for original: URL) -> String {
        let inputBase = original.deletingPathExtension().lastPathComponent
        let base = inputBase.hasSuffix("_脱敏")
            ? String(inputBase.dropLast("_脱敏".count))
            : inputBase
        let ext = original.pathExtension
        return "\(base)_脱敏恢复版.\(ext)"
    }
}
