import Foundation

final class SystemProxyManager {
    private let networkServiceName: String?

    init(networkServiceName: String? = nil) {
        self.networkServiceName = networkServiceName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setHTTPProxy(host: String, port: Int) throws {
        try runForTargetNetworkServices { networkServiceName in
            ["setwebproxy", networkServiceName, host, String(port)]
        }
    }

    func setSOCKSProxy(host: String, port: Int) throws {
        try runForTargetNetworkServices { networkServiceName in
            ["setsocksfirewallproxy", networkServiceName, host, String(port)]
        }
    }

    func setPACURL(_ url: String) throws {
        try runForTargetNetworkServices { networkServiceName in
            ["setautoproxyurl", networkServiceName, url]
        }
    }

    func disableWebProxy() throws {
        try runForTargetNetworkServices { networkServiceName in
            ["setwebproxystate", networkServiceName, "off"]
        }
    }

    func disableSOCKSProxy() throws {
        try runForTargetNetworkServices { networkServiceName in
            ["setsocksfirewallproxystate", networkServiceName, "off"]
        }
    }

    func disableAutoProxy() throws {
        try runForTargetNetworkServices { networkServiceName in
            ["setautoproxystate", networkServiceName, "off"]
        }
    }

    private func runForTargetNetworkServices(_ arguments: (String) -> [String]) throws {
        let networkServices = try targetNetworkServices()
        var errors: [String] = []
        var successCount = 0

        for networkServiceName in networkServices {
            do {
                try runNetworksetup(arguments(networkServiceName))
                successCount += 1
            } catch {
                errors.append("\(networkServiceName): \(error.localizedDescription)")
            }
        }

        if successCount == 0 {
            let message = errors.isEmpty ? "未找到可用网络服务" : errors.joined(separator: "\n")
            throw NSError(
                domain: "SystemProxyManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func targetNetworkServices() throws -> [String] {
        if let networkServiceName, !networkServiceName.isEmpty {
            return [networkServiceName]
        }

        let networkServices = try listAllEnabledNetworkServices()
        guard !networkServices.isEmpty else {
            throw NSError(
                domain: "SystemProxyManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "未找到启用中的网络服务"]
            )
        }
        return networkServices
    }

    private func listAllEnabledNetworkServices() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallnetworkservices"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SystemProxyManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty &&
                !$0.hasPrefix("An asterisk") &&
                !$0.hasPrefix("*")
            }
    }

    private func runNetworksetup(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SystemProxyManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
        }
    }
}
