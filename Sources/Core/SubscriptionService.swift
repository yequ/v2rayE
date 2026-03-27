import Foundation

final class SubscriptionService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refresh(profile: SubscriptionProfile) async throws -> SubscriptionProfile {
        guard let url = URL(string: profile.url) else {
            throw SubscriptionError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let content = decodeSubscription(data: data)
        let nodes = try parseNodes(from: content)

        var updated = profile
        updated.nodes = nodes
        updated.lastUpdatedAt = Date()
        return updated
    }

    private func decodeSubscription(data: Data) -> String {
        if let plain = String(data: data, encoding: .utf8), plain.contains("://") {
            return plain
        }

        if let encoded = String(data: data, encoding: .utf8),
           let decodedData = Data(base64Encoded: encoded.replacingOccurrences(of: "\n", with: "")),
           let decoded = String(data: decodedData, encoding: .utf8) {
            return decoded
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func parseNodes(from content: String) throws -> [ProxyNode] {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let nodes = lines.compactMap(parseNode(from:))
        if nodes.isEmpty {
            throw SubscriptionError.noValidNodes
        }
        return nodes
    }

    private func parseNode(from line: String) -> ProxyNode? {
        guard line.hasPrefix("vmess://") else { return nil }
        let payload = String(line.dropFirst("vmess://".count))
        guard let data = Data(base64Encoded: normalizeBase64(payload)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let address = json["add"] as? String ?? ""
        let port = Int(json["port"] as? String ?? "") ?? (json["port"] as? Int ?? 0)
        let userId = json["id"] as? String ?? ""
        guard !address.isEmpty, port > 0, !userId.isEmpty else {
            return nil
        }

        return ProxyNode(
            name: json["ps"] as? String ?? address,
            address: address,
            port: port,
            userId: userId,
            alterId: Int(json["aid"] as? String ?? "") ?? (json["aid"] as? Int ?? 0),
            security: json["scy"] as? String ?? "auto",
            network: json["net"] as? String ?? "tcp",
            remark: json["host"] as? String ?? ""
        )
    }

    private func normalizeBase64(_ raw: String) -> String {
        let remainder = raw.count % 4
        guard remainder != 0 else { return raw }
        return raw + String(repeating: "=", count: 4 - remainder)
    }
}

enum SubscriptionError: LocalizedError {
    case invalidURL
    case noValidNodes

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "订阅链接无效"
        case .noValidNodes:
            return "订阅内容中没有可用 vmess 节点"
        }
    }
}
