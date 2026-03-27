import Foundation
import Network

final class PACServer {
    private let port: UInt16
    private let pacFileURL: URL
    private var listener: NWListener?

    init(port: UInt16 = 8090, pacFileURL: URL) {
        self.port = port
        self.pacFileURL = pacFileURL
    }

    var pacURLString: String {
        "http://127.0.0.1:\(port)/proxy.pac"
    }

    func start() throws {
        if listener != nil { return }

        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self = self else {
                connection.cancel()
                return
            }

            let pacContent = (try? String(contentsOf: self.pacFileURL, encoding: .utf8)) ?? "function FindProxyForURL(url, host) { return \"DIRECT\"; }"
            let body = pacContent.data(using: .utf8) ?? Data()
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var response = Data(header.utf8)
            response.append(body)

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
