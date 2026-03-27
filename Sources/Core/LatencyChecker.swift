import Foundation

final class LatencyChecker {
    private var timer: Timer?
    var onLatencyUpdate: ((Int) -> Void)?

    func startMonitoring(interval: TimeInterval = 5.0) {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkLatency()
        }
        checkLatency()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkLatency() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let latency = self?.pingGoogle() ?? -1
            DispatchQueue.main.async {
                self?.onLatencyUpdate?(latency)
            }
        }
    }

    private func pingGoogle() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "2000", "8.8.8.8"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return -1 }

            // 从 "time=xx.xx ms" 中提取延迟
            if let regex = try? NSRegularExpression(pattern: "time=(\\d+\\.?\\d*) ms"),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output),
               let latency = Double(output[range]) {
                return Int(latency)
            }
        } catch {
            return -1
        }

        return -1
    }
}
