import Foundation

final class V2RayConfigBuilder {
    func build(for node: ProxyNode, socksPort: Int, httpPort: Int, proxyMode: ProxyMode) throws -> Data {
        let outbound = buildOutbound(for: node)

        let payload: [String: Any] = [
            "log": [
                "loglevel": "warning"
            ],
            "inbounds": [
                [
                    "tag": "socks-in",
                    "port": socksPort,
                    "listen": "127.0.0.1",
                    "protocol": "socks",
                    "settings": [
                        "auth": "noauth",
                        "udp": true
                    ],
                    "sniffing": [
                        "enabled": true,
                        "destOverride": ["http", "tls"]
                    ]
                ],
                [
                    "tag": "http-in",
                    "port": httpPort,
                    "listen": "127.0.0.1",
                    "protocol": "http",
                    "settings": [:]
                ]
            ],
            "outbounds": [
                outbound,
                [
                    "tag": "direct",
                    "protocol": "freedom",
                    "settings": [:]
                ]
            ],
            "routing": routingPayload(for: proxyMode)
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private func buildOutbound(for node: ProxyNode) -> [String: Any] {
        switch node.proxyProtocol {
        case .vmess:
            return buildVmessOutbound(for: node)
        case .vless:
            return buildVlessOutbound(for: node)
        }
    }

    private func buildVmessOutbound(for node: ProxyNode) -> [String: Any] {
        var outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "vmess",
            "settings": [
                "vnext": [
                    [
                        "address": node.address,
                        "port": node.port,
                        "users": [
                            [
                                "id": node.userId,
                                "alterId": node.alterId,
                                "security": node.security
                            ]
                        ]
                    ]
                ]
            ]
        ]

        outbound["streamSettings"] = buildStreamSettings(for: node)
        return outbound
    }

    private func buildVlessOutbound(for node: ProxyNode) -> [String: Any] {
        var user: [String: Any] = [
            "id": node.userId,
            "encryption": "none"
        ]
        if !node.flow.isEmpty {
            user["flow"] = node.flow
        }

        var outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "vless",
            "settings": [
                "vnext": [
                    [
                        "address": node.address,
                        "port": node.port,
                        "users": [user]
                    ]
                ]
            ]
        ]

        outbound["streamSettings"] = buildStreamSettings(for: node)
        return outbound
    }

    private func buildStreamSettings(for node: ProxyNode) -> [String: Any] {
        var streamSettings: [String: Any] = [
            "network": node.network
        ]

        // 配置 security 层
        if node.security == "reality" {
            streamSettings["security"] = "reality"
            streamSettings["realitySettings"] = buildRealitySettings(for: node)
        } else if node.security == "tls" {
            streamSettings["security"] = "tls"
            streamSettings["tlsSettings"] = buildTlsSettings(for: node)
        }

        // 配置传输层
        if node.network == "ws" {
            streamSettings["wsSettings"] = buildWsSettings(for: node)
        } else if node.network == "grpc" {
            streamSettings["grpcSettings"] = buildGrpcSettings(for: node)
        }

        return streamSettings
    }

    private func buildRealitySettings(for node: ProxyNode) -> [String: Any] {
        var settings: [String: Any] = [
            "show": false,
            "fingerprint": node.fingerprint.isEmpty ? "chrome" : node.fingerprint
        ]

        if !node.sni.isEmpty {
            settings["serverName"] = node.sni
        }
        if !node.publicKey.isEmpty {
            settings["publicKey"] = node.publicKey
        }
        settings["shortId"] = ""
        settings["spiderX"] = ""

        return settings
    }

    private func buildTlsSettings(for node: ProxyNode) -> [String: Any] {
        var settings: [String: Any] = [
            "allowInsecure": false
        ]

        if !node.sni.isEmpty {
            settings["serverName"] = node.sni
        }

        if !node.alpn.isEmpty {
            settings["alpn"] = node.alpn.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        return settings
    }

    private func buildWsSettings(for node: ProxyNode) -> [String: Any] {
        var settings: [String: Any] = [:]

        if !node.headerPath.isEmpty {
            settings["path"] = node.headerPath
        }

        if !node.headerHost.isEmpty {
            settings["headers"] = [
                "Host": node.headerHost
            ]
        }

        return settings
    }

    private func buildGrpcSettings(for node: ProxyNode) -> [String: Any] {
        var settings: [String: Any] = [:]

        if !node.headerPath.isEmpty {
            settings["serviceName"] = node.headerPath
        }

        return settings
    }

    private func routingPayload(for proxyMode: ProxyMode) -> [String: Any] {
        var rules: [[String: Any]] = [
            [
                "type": "field",
                "inboundTag": ["api"],
                "outboundTag": "direct"
            ]
        ]

        // PAC 模式不使用 routing
        if proxyMode == .pac {
            return [:]
        }

        return [
            "domainStrategy": "IPIfNonMatch",
            "rules": rules
        ]
    }
}
