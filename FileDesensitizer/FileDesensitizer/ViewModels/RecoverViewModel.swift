import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RecoverViewModel: ObservableObject {

    @Published var maskedFileURL: URL?
    @Published var mappingFileURL: URL?
    @Published var maskedFileName: String = ""
    @Published var mappingFileName: String = ""

    @Published var isProcessing = false
    @Published var progressMessage = ""
    @Published var result: ProcessingResult?
    @Published var errorMessage: String?

    @Published var currentStep: Step = .upload

    private let recover = RecoverService()
    private var workingOutputDirectory: URL?

    enum Step {
        case upload
        case result
    }

    var isReadyToProcess: Bool {
        maskedFileURL != nil && mappingFileURL != nil
    }

    func loadMaskedFile(url: URL) {
        guard FileFormatUtils.isSupported(url: url) else {
            errorMessage = ParseError.unsupportedFormat.errorDescription
            return
        }
        maskedFileURL = url
        maskedFileName = url.lastPathComponent
        errorMessage = nil
    }

    func loadMappingFile(url: URL) {
        mappingFileURL = url
        mappingFileName = url.lastPathComponent
        errorMessage = nil
    }

    func startRecover() {
        guard let maskedURL = maskedFileURL,
              let mappingURL = mappingFileURL else { return }

        isProcessing = true
        progressMessage = "正在恢复数据..."
        errorMessage = nil

        let outputDir: URL
        do {
            cleanupWorkingDirectory()
            outputDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FileDesensitizer-Recover-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: outputDir,
                withIntermediateDirectories: true
            )
            workingOutputDirectory = outputDir
        } catch {
            errorMessage = "无法创建临时输出目录：\(error.localizedDescription)"
            isProcessing = false
            currentStep = .result
            return
        }

        let service = recover
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try service.recover(
                    maskedFileURL: maskedURL,
                    mappingTableURL: mappingURL,
                    outputDir: outputDir)

                DispatchQueue.main.async {
                    self.result = result
                    self.isProcessing = false
                    self.progressMessage = ""
                    self.currentStep = .result
                }
            } catch {
                DispatchQueue.main.async {
                    self.cleanupWorkingDirectory()
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                    self.currentStep = .result
                }
            }
        }
    }

    func reset() {
        cleanupWorkingDirectory()
        maskedFileURL = nil
        mappingFileURL = nil
        maskedFileName = ""
        mappingFileName = ""
        isProcessing = false
        progressMessage = ""
        result = nil
        errorMessage = nil
        currentStep = .upload
    }

    private func cleanupWorkingDirectory() {
        guard let directory = workingOutputDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        workingOutputDirectory = nil
    }
}
