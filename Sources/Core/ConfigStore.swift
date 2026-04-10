import Foundation

final class ConfigStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let preferredCoreNames = ["xray", "v2ray"]

    private let supportRootURL: URL
    private let configURL: URL
    private let generatedConfigURL: URL
    private let coreDirectoryURL: URL

    init() {
        let supportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("v2rayE", isDirectory: true)
        self.supportRootURL = supportRoot
        self.configURL = supportRoot.appendingPathComponent("app-config.json")
        self.generatedConfigURL = supportRoot.appendingPathComponent("generated-v2ray-config.json")
        self.coreDirectoryURL = supportRoot.appendingPathComponent("core", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try? prepareDirectories(root: supportRoot)
        try? bootstrapPackagedAssetsIfNeeded()
    }

    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else {
            return .default
        }
        return (try? decoder.decode(AppConfig.self, from: data)) ?? .default
    }

    func save(_ config: AppConfig) throws {
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    func saveGeneratedCoreConfig(_ payload: Data) throws -> URL {
        try payload.write(to: generatedConfigURL, options: .atomic)
        return generatedConfigURL
    }

    func generatedCoreConfigPath() -> URL {
        generatedConfigURL
    }

    func coreExecutableURL() -> URL {
        coreExecutableURL(named: preferredCoreNames[0])
    }

    func discoverCoreExecutableURL() -> URL? {
        for url in bundledCoreExecutableURLs() where isFile(at: url) {
            return url
        }

        for name in preferredCoreNames {
            let directURL = coreExecutableURL(named: name)
            if fileExists(at: directURL) && isFile(at: directURL) {
                return directURL
            }

            let nestedURL = directURL.appendingPathComponent(name)
            if fileExists(at: nestedURL) && isFile(at: nestedURL) {
                return nestedURL
            }
        }

        let searchPaths: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/xray"),
            URL(fileURLWithPath: "/usr/local/bin/xray"),
            URL(fileURLWithPath: "/usr/bin/xray"),
            URL(fileURLWithPath: "/usr/local/bin/v2ray"),
            URL(fileURLWithPath: "/opt/homebrew/bin/v2ray"),
            URL(fileURLWithPath: "/usr/bin/v2ray")
        ]
        for path in searchPaths where fileExists(at: path) {
            return path
        }

        if let path = searchInCommonInstallLocations() {
            return path
        }

        return nil
    }

    func discoverCoreType() -> ProxyCoreType? {
        guard let executableURL = discoverCoreExecutableURL() else {
            return nil
        }

        switch executableURL.lastPathComponent.lowercased() {
        case "xray":
            return .xray
        case "v2ray":
            return .v2ray
        default:
            return nil
        }
    }

    private func coreExecutableURL(named name: String) -> URL {
        coreDirectoryURL.appendingPathComponent(name)
    }

    private func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func isFile(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    func isExecutable(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    private func searchInCommonInstallLocations() -> URL? {
        let possibleDirectories = [
            "/usr/local/xray",
            "/opt/xray",
            "~/Applications/xray",
            "/Applications/xray.app/Contents/MacOS",
            "/usr/local/v2ray",
            "/opt/v2ray",
            "~/Applications/v2ray",
            "/Applications/v2ray.app/Contents/MacOS"
        ]

        for directory in possibleDirectories {
            let expandedPath = (directory as NSString).expandingTildeInPath
            for name in preferredCoreNames {
                let coreURL = URL(fileURLWithPath: expandedPath).appendingPathComponent(name)
                if fileManager.fileExists(atPath: coreURL.path) {
                    return coreURL
                }
            }
        }

        if let home = fileManager.homeDirectoryForCurrentUser.path.removingPercentEncoding {
            for name in preferredCoreNames {
                let homeCore = URL(fileURLWithPath: home)
                    .appendingPathComponent(".local/bin")
                    .appendingPathComponent(name)
                if fileManager.fileExists(atPath: homeCore.path) {
                    return homeCore
                }
            }
        }

        return nil
    }

    func coreAssetsDirectoryURL() -> URL {
        coreDirectoryURL
    }

    private func prepareDirectories(root: URL) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coreDirectoryURL, withIntermediateDirectories: true)
    }

    private func bootstrapPackagedAssetsIfNeeded() throws {
        guard let packagedAssetsURL = packagedAssetsDirectoryURL() else {
            return
        }

        let packagedCoreURL = packagedCoreExecutableURL(from: packagedAssetsURL)
        let packagedPACURL = packagedAssetsURL.appendingPathComponent("proxy.js")
        let targetPACURL = supportRootURL.appendingPathComponent("proxy.js")

        if let packagedCoreURL {
            let targetCoreURL = coreExecutableURL(named: packagedCoreURL.lastPathComponent)
            try copyFileIfNeeded(from: packagedCoreURL, to: targetCoreURL, executable: true)
        }
        try copyFileIfNeeded(from: packagedPACURL, to: targetPACURL, executable: false)
    }

    private func packagedAssetsDirectoryURL() -> URL? {
        let fallbackExecutableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableURL = Bundle.main.executableURL ?? fallbackExecutableURL
        let executableDirectoryURL = executableURL.deletingLastPathComponent()

        let candidates = [
            executableDirectoryURL.appendingPathComponent("assets", isDirectory: true),
            executableDirectoryURL
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("assets", isDirectory: true)
                .standardizedFileURL
        ]

        return candidates.first(where: { isDirectory(at: $0) })
    }

    private func packagedCoreExecutableURL(from packagedAssetsURL: URL) -> URL? {
        let fallbackExecutableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableURL = Bundle.main.executableURL ?? fallbackExecutableURL
        let executableDirectoryURL = executableURL.deletingLastPathComponent()

        let candidates = preferredCoreNames.flatMap { name in
            [
                packagedAssetsURL.appendingPathComponent("core", isDirectory: true).appendingPathComponent(name),
                executableDirectoryURL
                    .appendingPathComponent("..", isDirectory: true)
                    .appendingPathComponent("Helpers", isDirectory: true)
                    .appendingPathComponent(name)
                    .standardizedFileURL
            ]
        }

        return candidates.first(where: { isFile(at: $0) })
    }

    private func bundledCoreExecutableURLs() -> [URL] {
        let fallbackExecutableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableURL = Bundle.main.executableURL ?? fallbackExecutableURL
        let executableDirectoryURL = executableURL.deletingLastPathComponent()

        return preferredCoreNames.map { name in
            executableDirectoryURL
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(name)
                .standardizedFileURL
        }
    }

    private func copyFileIfNeeded(from sourceURL: URL, to destinationURL: URL, executable: Bool) throws {
        guard isFile(at: sourceURL) else {
            return
        }

        guard !fileExists(at: destinationURL) else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        if executable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        }
    }
}
