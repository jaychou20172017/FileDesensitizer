import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DesensitizeViewModel: ObservableObject {

    // MARK: - File state
    @Published var selectedFileURL: URL?
    @Published var fileName: String = ""
    @Published var fileSize: String = ""
    @Published var fileType: FileFormatUtils.FileType = .unknown

    // MARK: - Analysis state
    @Published var parsedFile: ParsedFile?
    @Published var availableSheets: [String] = []
    @Published var selectedSheet: String = ""
    @Published var allFields: [FieldInfo] = []
    @Published var fieldSelection: Set<UUID> = []

    // MARK: - Process state
    @Published var isProcessing = false
    @Published var progressMessage = ""
    @Published var result: ProcessingResult?
    @Published var errorMessage: String?

    // MARK: - Step tracking
    @Published var currentStep: Step = .upload

    private let parser = FileParserService()
    private let detector = SensitiveDetector()
    private let desensitize = DesensitizeService()
    private var workingOutputDirectory: URL?

    enum Step {
        case upload
        case selectSheet
        case selectFields
        case result
    }

    var isReadyToProcess: Bool {
        !fieldSelection.isEmpty
    }

    var selectedFields: [FieldInfo] {
        allFields.filter { fieldSelection.contains($0.id) }
    }

    var sensitiveFields: [FieldInfo] {
        allFields.filter { $0.isSensitive }
    }

    // MARK: - Actions

    func loadFile(url: URL) {
        reset()
        guard FileFormatUtils.isSupported(url: url) else {
            errorMessage = ParseError.unsupportedFormat.errorDescription
            return
        }
        selectedFileURL = url
        fileName = url.lastPathComponent
        fileSize = FileFormatUtils.displayFileSize(url)
        fileType = FileFormatUtils.detectFileType(from: url)

        do {
            let parsed = try parser.parse(url: url)
            parsedFile = parsed
            availableSheets = parsed.sheets.map { $0.name }

            if fileType == .excel && availableSheets.count > 1 {
                currentStep = .selectSheet
            } else {
                selectedSheet = availableSheets.first ?? ""
                analyzeFields()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectAndAnalyzeSheet(_ sheetName: String) {
        selectedSheet = sheetName
        analyzeFields()
    }

    private func analyzeFields() {
        guard let parsed = parsedFile else { return }

        let target: ParsedFile
        if fileType == .excel, let sheet = parsed.sheets.first(where: { $0.name == selectedSheet }) {
            target = ParsedFile(fileName: parsed.fileName, fileType: parsed.fileType,
                                sheets: [sheet], textContent: parsed.textContent)
        } else {
            target = parsed
        }

        allFields = detector.analyze(target)
        fieldSelection = Set(allFields.filter { $0.isSensitive }.map { $0.id })
        currentStep = .selectFields
    }

    func toggleSelectAll() {
        if fieldSelection.count == allFields.count {
            fieldSelection = []
        } else {
            fieldSelection = Set(allFields.map { $0.id })
        }
    }

    func toggleField(_ id: UUID) {
        if fieldSelection.contains(id) {
            fieldSelection.remove(id)
        } else {
            fieldSelection.insert(id)
        }
    }

    func startDesensitize() {
        guard let url = selectedFileURL, let parsed = parsedFile, !fieldSelection.isEmpty else { return }
        isProcessing = true
        progressMessage = "正在脱敏处理..."
        errorMessage = nil

        let outputDir: URL
        do {
            cleanupWorkingDirectory()
            outputDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FileDesensitizer-\(UUID().uuidString)", isDirectory: true)
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

        let fields = selectedFields
        let service = desensitize
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try service.desensitize(
                    parsedFile: parsed, originalFileURL: url,
                    selectedFields: fields, outputDir: outputDir)

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
        selectedFileURL = nil
        fileName = ""
        fileSize = ""
        fileType = .unknown
        parsedFile = nil
        availableSheets = []
        selectedSheet = ""
        allFields = []
        fieldSelection = []
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
