import Foundation

enum PythonRuntimeError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "缺少内置文档处理运行时，请重新安装文件脱敏工具"
    }
}

enum PythonRuntime {
    static func configure(_ process: Process) throws {
        if let resourceURL = Bundle.main.resourceURL {
            let runtimeURL = resourceURL.appendingPathComponent("PythonRuntime", isDirectory: true)
            let executableURL = runtimeURL.appendingPathComponent("bin/python3")

            if FileManager.default.isExecutableFile(atPath: executableURL.path) {
                process.executableURL = executableURL

                var environment = ProcessInfo.processInfo.environment
                environment["PYTHONHOME"] = runtimeURL.path
                environment["PYTHONNOUSERSITE"] = "1"
                environment["PYTHONDONTWRITEBYTECODE"] = "1"
                process.environment = environment
                return
            }
        }

#if DEBUG
        let developmentPython = "/usr/bin/python3"
        if FileManager.default.isExecutableFile(atPath: developmentPython) {
            process.executableURL = URL(fileURLWithPath: developmentPython)
            return
        }
#endif

        throw PythonRuntimeError.unavailable
    }
}
