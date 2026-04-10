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

        if let encoded = String(data: data, encoding: .utf8) {
            let normalized = normalizeSubscriptionBase64(encoded)

            if let decodedData = Data(base64Encoded: normalized),
               let decoded = String(data: decodedData, encoding: .utf8) {
                return decoded
            }

            let urlSafeNormalized = normalizeBase64(
                normalized
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
            )
            if let decodedData = Data(base64Encoded: urlSafeNormalized),
               let decoded = String(data: decodedData, encoding: .utf8) {
                return decoded
            }
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
        if line.hasPrefix("vmess://") {
            return parseVmessNode(from: line)
        } else if line.hasPrefix("vless://") {
            return parseVlessNode(from: line)
        }
        return nil
    }

    private func parseVmessNode(from line: String) -> ProxyNode? {
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
            remark: json["host"] as? String ?? "",
            proxyProtocol: .vmess
        )
    }

    private func parseVlessNode(from line: String) -> ProxyNode? {
        // vless://UUID@address:port?params#remark
        let payload = String(line.dropFirst("vless://".count))

        // 分离参数和备注
        let partsWithRemark = payload.components(separatedBy: "#")
        let mainPart = partsWithRemark[0]
        let remark = partsWithRemark.count > 1 ? (partsWithRemark[1].removingPercentEncoding ?? partsWithRemark[1]) : ""

        // 分离 UUID@address:port 和参数
        let partsWithParams = mainPart.components(separatedBy: "?")
        let credentialPart = partsWithParams[0]
        let queryString = partsWithParams.count > 1 ? partsWithParams[1] : ""

        // 解析 UUID@address:port
        let credentialParts = credentialPart.components(separatedBy: "@")
        guard credentialParts.count == 2 else { return nil }
        let userId = credentialParts[0]

        let addressPort = credentialParts[1]
        guard let lastColonIndex = addressPort.lastIndex(of: ":") else { return nil }
        let address = String(addressPort[..<lastColonIndex])
        let portString = String(addressPort[addressPort.index(after: lastColonIndex)...])
        guard let port = Int(portString), port > 0 else { return nil }

        guard !address.isEmpty, !userId.isEmpty else { return nil }

        // 解析参数
        var params: [String: String] = [:]
        if !queryString.isEmpty {
            let pairs = queryString.components(separatedBy: "&")
            for pair in pairs {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    let key = kv[0]
                    let value = kv[1].removingPercentEncoding ?? kv[1]
                    params[key] = value
                }
            }
        }

        let name = remark.isEmpty ? address : remark
        let security = params["security"] ?? "tls"
        let network = params["type"] ?? "tcp"
        let flow = params["flow"] ?? ""
        let sni = params["sni"] ?? ""
        let alpn = params["alpn"] ?? ""
        let fingerprint = params["fp"] ?? ""
        let publicKey = params["pbk"] ?? ""
        let headerHost = params["host"] ?? ""
        let headerPath = params["path"] ?? ""

        return ProxyNode(
            name: name,
            address: address,
            port: port,
            userId: userId,
            alterId: 0,
            security: security,
            network: network,
            remark: remark,
            proxyProtocol: .vless,
            flow: flow,
            sni: sni,
            alpn: alpn,
            fingerprint: fingerprint,
            publicKey: publicKey,
            headerHost: headerHost,
            headerPath: headerPath
        )
    }

    private func normalizeSubscriptionBase64(_ raw: String) -> String {
        let compact = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return normalizeBase64(compact)
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
            return "订阅内容中没有可用节点（需 vmess 或 vless 协议）"
        }
    }
}
