import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let loadedFileName: String
    let fileSize: String
    let acceptedTypes: [UTType]
    let formatHint: String
    let onFileSelected: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            if !loadedFileName.isEmpty {
                fileLoadedView
            } else {
                dropPromptView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: SwiftUI.StrokeStyle(lineWidth: 2, dash: loadedFileName.isEmpty ? [6, 4] : [])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onTapGesture {
            openFilePicker()
        }
    }

    private var dropPromptView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("拖拽文件到此处，或点击选择")
                .font(.body)
                .foregroundColor(.secondary)
            Text(formatHint)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var fileLoadedView: some View {
        HStack(spacing: 16) {
            Image(systemName: fileIcon)
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(loadedFileName)
                    .font(.headline)
                Text(fileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                openFilePicker()
            } label: {
                Text("更换")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
    }

    private var fileIcon: String {
        if loadedFileName.lowercased().hasSuffix(".xlsx") || loadedFileName.lowercased().hasSuffix(".xls") {
            return "tablecells"
        }
        return "doc"
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    onFileSelected(url)
                }
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = acceptedTypes
        panel.message = "选择要处理的文件"

        if panel.runModal() == .OK, let url = panel.url {
            onFileSelected(url)
        }
    }
}
