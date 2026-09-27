import SwiftUI

struct FieldSelectionView: View {
    let allFields: [FieldInfo]
    @Binding var selection: Set<UUID>
    let onToggleAll: () -> Void
    let onToggleField: (UUID) -> Void
    let onBack: () -> Void
    let onProcess: () -> Void
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            fieldList
            bottomBar
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("返回", systemImage: "chevron.left")
            }
            Spacer()
            Text("选择需要脱敏的字段")
                .font(.headline)
            Spacer()
            Button(action: onToggleAll) {
                Text(allSelected ? "取消全选" : "全选")
                    .font(.body)
            }
        }
    }

    private var allSelected: Bool {
        selection.count == allFields.count && !allFields.isEmpty
    }

    private var fieldList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(allFields) { field in
                    FieldRow(
                        field: field,
                        isSelected: selection.contains(field.id),
                        onToggle: { onToggleField(field.id) }
                    )
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
    }

    private var bottomBar: some View {
        HStack {
            Text("已选择 \(selection.count) / \(allFields.count) 个字段")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: onProcess) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    }
                    Text("开始脱敏")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selection.isEmpty || isProcessing)
        }
    }
}

struct FieldRow: View {
    let field: FieldInfo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(field.name)
                    .font(.body)
                Text(field.displaySource)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if field.isSensitive {
                ForEach(field.sensitiveTypes, id: \.self) { type in
                    Text(type.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
