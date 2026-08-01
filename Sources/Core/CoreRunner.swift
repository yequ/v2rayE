import Darwin
import Foundation

final class CoreRunner {
    private var process: Process?
    private var outputLogFileHandle: FileHandle?
    private var errorLogFileHandle: FileHandle?
    private let configStore: ConfigStore
    private var stdoutMonitorTask: Task<Void, Never>?

    var isRunning: Bool {
        process?.isRunning == true
    }

    var onErrorDetected: ((String) -> Void)?
    var onErrorRecovered: (() -> Void)?

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
            
            let outputLogURL = try makeCoreLogURL(fileName: "core-stdout.log")
            let errorLogURL = try makeCoreLogURL(fileName: "core-stderr.log")
            let errorHandle = try FileHandle(forWritingTo: errorLogURL)
            process.standardError = errorHandle

            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            let outputHandle = try FileHandle(forWritingTo: outputLogURL)
            self.outputLogFileHandle = outputHandle
            self.errorLogFileHandle = errorHandle

            startStdoutMonitor(pipe: stdoutPipe, logHandle: outputHandle)

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
                let stderrMsg = (try? String(contentsOf: errorLogURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                closeLogHandles()
                cancelStdoutMonitor()
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

    private var errorTimestamps: [Date] = []
    private var recoveryTask: Task<Void, Never>?
    private let errorWindowSeconds: TimeInterval = 30
    private let errorThreshold = 3

    private func startStdoutMonitor(pipe: Pipe, logHandle: FileHandle) {
        cancelStdoutMonitor()
        errorTimestamps.removeAll()
        recoveryTask?.cancel()
        stdoutMonitorTask = Task.detached { [weak self] in
            let errorPatterns = [
                "failed to process outbound traffic",
                "failed to find an available destination",
                "all retry attempts failed",
                "bad handshake",
                "connection refused",
                "i/o timeout",
                "no such host"
            ]
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    autoreleasepool {
                        if let data = (line + "\n").data(using: .utf8) {
                            try? logHandle.write(contentsOf: data)
                        }
                    }
                    let lowercased = line.lowercased()
                    for pattern in errorPatterns {
                        if lowercased.contains(pattern) {
                            guard let self else { break }
                            let now = Date()
                            self.errorTimestamps.append(now)
                            self.errorTimestamps = self.errorTimestamps.filter {
                                now.timeIntervalSince($0) < self.errorWindowSeconds
                            }
                            if self.errorTimestamps.count >= self.errorThreshold {
                                Task { @MainActor [weak self] in
                                    self?.onErrorDetected?(line)
                                }
                                self.errorTimestamps.removeAll()
                            }
                            self.scheduleRecoveryCheck()
                            break
                        }
                    }
                }
            } catch {}
        }
    }

    private func scheduleRecoveryCheck() {
        recoveryTask?.cancel()
        let windowSeconds = errorWindowSeconds
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(windowSeconds) * 1_000_000_000)
            guard let self else { return }
            let now = Date()
            self.errorTimestamps = self.errorTimestamps.filter {
                now.timeIntervalSince($0) < windowSeconds
            }
            if self.errorTimestamps.isEmpty {
                Task { @MainActor [weak self] in
                    self?.onErrorRecovered?()
                }
            }
        }
    }

    private func cancelStdoutMonitor() {
        stdoutMonitorTask?.cancel()
        stdoutMonitorTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        errorTimestamps.removeAll()
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

        cancelStdoutMonitor()
        closeLogHandles()
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

    private func makeCoreLogURL(fileName: String) throws -> URL {
        let logDirectoryURL = configStore.coreAssetsDirectoryURL().deletingLastPathComponent()
            .appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)

        let logURL = logDirectoryURL.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        try Data().write(to: logURL, options: .atomic)
        return logURL
    }

    private func closeLogHandles() {
        try? outputLogFileHandle?.close()
        try? errorLogFileHandle?.close()
        outputLogFileHandle = nil
        errorLogFileHandle = nil
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
