import SwiftUI
import UniformTypeIdentifiers

struct RecoverView: View {
    @StateObject private var vm = RecoverViewModel()
    @State private var saveMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            switch vm.currentStep {
            case .upload:
                uploadStep
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
        ScrollView {
            VStack(spacing: 20) {
                Text("数据恢复")
                    .font(.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("脱敏文件")
                        .font(.headline)
                    DropZoneView(
                        loadedFileName: vm.maskedFileName,
                        fileSize: "",
                        acceptedTypes: acceptedFileTypes,
                        formatHint: "当前仅支持 Excel（.xlsx）",
                        onFileSelected: { vm.loadMaskedFile(url: $0) }
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("映射表（.csv 或 .xlsx）")
                        .font(.headline)
                    DropZoneView(
                        loadedFileName: vm.mappingFileName,
                        fileSize: "",
                        acceptedTypes: [.spreadsheet, .commaSeparatedText],
                        formatHint: "支持映射表（.xlsx 或 .csv）",
                        onFileSelected: { vm.loadMappingFile(url: $0) }
                    )
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Spacer()
                    Button(action: { vm.startRecover() }) {
                        HStack {
                            if vm.isProcessing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            }
                            Text("开始恢复")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!vm.isReadyToProcess || vm.isProcessing)
                }
            }
        }
    }

    // MARK: - Result Step

    private var resultStep: some View {
        Group {
            if let result = vm.result {
                PreviewView(
                    result: result,
                    onSave: { saveRecoveredFile() },
                    onReset: { vm.reset() }
                )
            } else if let error = vm.errorMessage {
                VStack(spacing: 16) {
                    Text("恢复失败")
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

    private func saveRecoveredFile() {
        guard let result = vm.result, let outputURL = result.outputFileURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = outputURL.lastPathComponent
        panel.message = "选择保存位置"

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        if outputURL.standardizedFileURL == saveURL.standardizedFileURL {
            saveMessage = "恢复文件已保存到：\n\(saveURL.path)"
            return
        }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: saveURL.path) {
                try fileManager.removeItem(at: saveURL)
            }
            try fileManager.copyItem(at: outputURL, to: saveURL)
            saveMessage = "恢复文件已保存到：\n\(saveURL.path)"
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
