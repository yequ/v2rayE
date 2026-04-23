import Foundation
import Network

final class LatencyChecker {
    private let queue = DispatchQueue(label: "v2rayE.latency-checker", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var currentConnection: NWConnection?
    private var isChecking = false
    var onLatencyUpdate: ((Int) -> Void)?

    func startMonitoring(interval: TimeInterval = 5.0) {
        stopMonitoring()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.checkLatency()
        }
        self.timer = timer
        timer.resume()
    }

    func stopMonitoring() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        currentConnection?.cancel()
        currentConnection = nil
        isChecking = false
        onLatencyUpdate = nil
    }

    private func checkLatency() {
        guard !isChecking else { return }
        isChecking = true

        let startTime = DispatchTime.now()
        let connection = NWConnection(host: "8.8.8.8", port: 53, using: .tcp)
        currentConnection?.cancel()
        currentConnection = connection
        var hasFinished = false

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }

            switch state {
            case .ready:
                guard !hasFinished else { return }
                hasFinished = true
                let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
                let latency = Int(elapsed / 1_000_000)
                self.finishCheck(latency: latency, connection: connection)
            case .failed, .cancelled:
                guard !hasFinished else { return }
                hasFinished = true
                self.finishCheck(latency: -1, connection: connection)
            default:
                break
            }
        }

        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 2.5) { [weak self, weak connection] in
            guard let self, let connection else { return }
            guard !hasFinished else { return }
            hasFinished = true
            connection.cancel()
            self.finishCheck(latency: -1, connection: connection)
        }
    }

    private func finishCheck(latency: Int, connection: NWConnection?) {
        if currentConnection === connection {
            currentConnection = nil
        }
        isChecking = false

        connection?.stateUpdateHandler = nil
        connection?.cancel()

        DispatchQueue.main.async { [weak self] in
            self?.onLatencyUpdate?(latency)
        }
    }
}
