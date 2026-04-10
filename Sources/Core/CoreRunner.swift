import Darwin
import Foundation

final class CoreRunner {
    private var process: Process?
    private let configStore: ConfigStore

    var isRunning: Bool {
        process?.isRunning == true
    }

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func start(with configURL: URL) throws {
        stop()

        guard let executableURL = configStore.discoverCoreExecutableURL() else {
            throw CoreRunnerError.coreNotInstalled(configStore.coreExecutableURL().path)
        }

        try ensureExecutablePermissionIfNeeded(for: executableURL)
        try ensureConfigFileExists(configURL)

        var lastError: Error? = nil
        for attempt in 1...2 {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["run", "-config", configURL.path]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var environment = ProcessInfo.processInfo.environment
            environment["v2ray.location.asset"] = configStore.coreAssetsDirectoryURL().path
            environment["xray.location.asset"] = configStore.coreAssetsDirectoryURL().path
            process.environment = environment

            self.process = process
            do {
                try process.run()
                return
            } catch {
                lastError = error
                let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrMsg = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let nsError = error as NSError
                
                if attempt == 1 &&
                   ((nsError.domain == NSPOSIXErrorDomain && nsError.code == EACCES) ||
                    (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError)) {
                    try ensureExecutablePermissionIfNeeded(for: executableURL)
                    continue
                }
                
                if !stderrMsg.isEmpty {
                    throw CoreRunnerError.coreLaunchFailed(stderrMsg)
                }
                throw error
            }
        }
        
        if let error = lastError {
            throw error
        }
    }

    func stop() {
        guard let process else { return }

        if process.isRunning {
            process.terminate()
            waitForProcessToExit(process, timeout: 1.0)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            waitForProcessToExit(process, timeout: 0.3)
        }

        self.process = nil
    }

    private func waitForProcessToExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func ensureExecutablePermissionIfNeeded(for executableURL: URL) throws {
        let path = executableURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard !FileManager.default.isExecutableFile(atPath: path) else { return }

        let coreDir = configStore.coreAssetsDirectoryURL().path
        if path.hasPrefix(coreDir) {
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", path]
            
            do {
                try chmodProcess.run()
                chmodProcess.waitUntilExit()
                Thread.sleep(forTimeInterval: 0.2)
            } catch {
                throw CoreRunnerError.corePermissionDenied(path)
            }
        } else {
            throw CoreRunnerError.corePermissionDenied(path)
        }
    }

    private func ensureConfigFileExists(_ configURL: URL) throws {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw CoreRunnerError.configFileMissing(configURL.path)
        }
    }

}

enum CoreRunnerError: LocalizedError {
    case coreNotInstalled(String)
    case corePermissionDenied(String)
    case configFileMissing(String)
    case coreLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .coreNotInstalled(let path):
            return "未找到可用代理内核，请将 xray 或 v2ray 可执行文件放到 \(path)"
        case .corePermissionDenied(let path):
            return "代理内核没有执行权限，请执行 chmod +x \"\(path)\""
        case .configFileMissing(let path):
            return "配置文件丢失：\(path)"
        case .coreLaunchFailed(let reason):
            return "代理内核启动失败：\(reason)"
        }
    }
}
