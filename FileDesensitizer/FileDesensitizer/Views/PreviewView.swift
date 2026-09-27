import SwiftUI

struct PreviewView: View {
    let result: ProcessingResult
    let onSave: () -> Void
    let onReset: () -> Void

    @State private var currentPage = 0
    private let pageSize = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryCard
            comparisonTable
            actionBar
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 24) {
            statItem(value: "\(result.totalFields)", label: "处理字段")
            statItem(value: "\(result.totalRows)", label: "映射条目")
            statItem(value: "\(uniqueFields)", label: "唯一字段")
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.06))
        )
    }

    private var uniqueFields: Int {
        Set(result.mappings.map { $0.fieldName }).count
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var comparisonTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("脱敏前后对比")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        tableHeader("字段名", width: 120)
                        tableHeader("原始值", width: nil)
                        tableHeader("脱敏值", width: nil)
                    }
                    .background(Color.secondary.opacity(0.1))

                    Divider()

                    ForEach(pagedMappings) { entry in
                        HStack(spacing: 0) {
                            tableCell(entry.fieldName, width: 120, color: .secondary)
                            tableCell(entry.originalValue, width: nil, color: .primary)
                            tableCell(entry.maskedValue, width: nil, color: .orange)
                        }
                        Divider()
                    }
                }
            }

            if totalPages > 1 {
                pageControl
            }
        }
    }

    private var totalPages: Int {
        max(1, (result.mappings.count + pageSize - 1) / pageSize)
    }

    private var pagedMappings: [MappingEntry] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, result.mappings.count)
        return Array(result.mappings[start..<end])
    }

    private func tableHeader(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func tableCell(_ text: String, width: CGFloat?, color: Color) -> some View {
        Text(text.isEmpty ? "-" : text)
            .font(.system(.body, design: .monospaced))
            .fontWeight(color == .primary ? .regular : .medium)
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private var pageControl: some View {
        HStack {
            Button {
                if currentPage > 0 { currentPage -= 1 }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage == 0)

            Text("第 \(currentPage + 1) / \(totalPages) 页")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                if currentPage < totalPages - 1 { currentPage += 1 }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= totalPages - 1)
        }
    }

    private var actionBar: some View {
        HStack {
            Button(action: onReset) {
                Text("处理新文件")
            }

            Spacer()

            Button(action: onSave) {
                Label("保存结果", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
