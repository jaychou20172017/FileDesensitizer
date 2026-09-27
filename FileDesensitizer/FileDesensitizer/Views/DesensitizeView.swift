import SwiftUI
import UniformTypeIdentifiers

struct DesensitizeView: View {
    @StateObject private var vm = DesensitizeViewModel()
    @State private var saveMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            switch vm.currentStep {
            case .upload, .selectSheet:
                uploadStep
            case .selectFields:
                fieldStep
            case .result:
                resultStep
            }
        }
        .padding(16)
        .alert("保存结果", isPresented: saveAlertBinding) {
            Button("确定", role: .cancel) { saveMessage = nil }
        } message: {
            Text(saveMessage ?? "")
        }
    }

    // MARK: - Upload Step

    private var uploadStep: some View {
        VStack(spacing: 20) {
            Text("脱敏处理")
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            DropZoneView(
                loadedFileName: vm.fileName,
                fileSize: vm.fileSize,
                acceptedTypes: acceptedFileTypes,
                formatHint: "当前仅支持 Excel（.xlsx）",
                onFileSelected: { vm.loadFile(url: $0) }
            )

            if vm.fileType == .excel && !vm.availableSheets.isEmpty && vm.currentStep == .selectSheet {
                sheetSelector
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()
        }
    }

    private var sheetSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择 Sheet")
                .font(.headline)
            Picker("Sheet", selection: Binding(
                get: { vm.selectedSheet },
                set: { vm.selectAndAnalyzeSheet($0) }
            )) {
                ForEach(vm.availableSheets, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    // MARK: - Field Step

    private var fieldStep: some View {
        FieldSelectionView(
            allFields: vm.allFields,
            selection: $vm.fieldSelection,
            onToggleAll: { vm.toggleSelectAll() },
            onToggleField: { vm.toggleField($0) },
            onBack: { vm.currentStep = .upload },
            onProcess: { vm.startDesensitize() },
            isProcessing: vm.isProcessing
        )
    }

    // MARK: - Result Step

    private var resultStep: some View {
        Group {
            if let result = vm.result {
                PreviewView(
                    result: result,
                    onSave: { saveResult() },
                    onReset: { vm.reset() }
                )
            } else if let error = vm.errorMessage {
                VStack(spacing: 16) {
                    Text("处理失败")
                        .font(.headline)
                    Text(error)
                        .foregroundColor(.red)
                    Button("重试") { vm.reset() }
                }
            } else {
                ProgressView("处理中...")
            }
        }
    }

    private func saveResult() {
        guard let result = vm.result, let outputURL = result.outputFileURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "保存到该目录"
        panel.message = "脱敏文件和映射表将保存到所选目录"

        guard panel.runModal() == .OK, let dirURL = panel.url else { return }

        var copies = [(source: outputURL,
                       destination: dirURL.appendingPathComponent(outputURL.lastPathComponent))]
        if let mappingURL = result.mappingFileURL {
            copies.append((source: mappingURL,
                           destination: dirURL.appendingPathComponent(mappingURL.lastPathComponent)))
        }

        let fileManager = FileManager.default
        let existingFiles = copies.filter {
            $0.source.standardizedFileURL != $0.destination.standardizedFileURL
                && fileManager.fileExists(atPath: $0.destination.path)
        }
        if !existingFiles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "目标目录中已有同名文件"
            alert.informativeText = existingFiles.map(\.destination.lastPathComponent)
                .joined(separator: "\n") + "\n\n是否覆盖？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            for copy in copies where copy.source.standardizedFileURL != copy.destination.standardizedFileURL {
                if fileManager.fileExists(atPath: copy.destination.path) {
                    try fileManager.removeItem(at: copy.destination)
                }
                try fileManager.copyItem(at: copy.source, to: copy.destination)
            }
            saveMessage = "脱敏文件和映射表已保存到：\n\(dirURL.path)"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private var saveAlertBinding: Binding<Bool> {
        Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )
    }

    private var acceptedFileTypes: [UTType] {
        [
            UTType(filenameExtension: "xlsx") ?? .spreadsheet
        ].compactMap { $0 }
    }
}
