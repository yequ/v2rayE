import Foundation

final class SystemProxyManager {
    private let networkServiceName: String

    init(networkServiceName: String = "Wi-Fi") {
        self.networkServiceName = networkServiceName
    }

    func setHTTPProxy(host: String, port: Int) throws {
        try runNetworksetup([
            "setwebproxy", networkServiceName, host, String(port)
        ])
    }

    func setSOCKSProxy(host: String, port: Int) throws {
        try runNetworksetup([
            "setsocksfirewallproxy", networkServiceName, host, String(port)
        ])
    }

    func setPACURL(_ url: String) throws {
        try runNetworksetup([
            "setautoproxyurl", networkServiceName, url
        ])
    }

    func disableWebProxy() throws {
        try runNetworksetup([
            "setwebproxystate", networkServiceName, "off"
        ])
    }

    func disableSOCKSProxy() throws {
        try runNetworksetup([
            "setsocksfirewallproxystate", networkServiceName, "off"
        ])
    }

    func disableAutoProxy() throws {
        try runNetworksetup([
            "setautoproxystate", networkServiceName, "off"
        ])
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
