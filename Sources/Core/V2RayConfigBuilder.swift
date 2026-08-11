import Foundation

final class V2RayConfigBuilder {
    func build(
        for node: ProxyNode,
        socksPort: Int,
        httpPort: Int,
        listenAddress: String,
        proxyMode: ProxyMode
    ) throws -> Data {
        let outbound = buildOutbound(for: node)

        let payload: [String: Any] = [
            "dns": [
                "servers": [
                    "8.8.8.8",
                    "1.1.1.1",
                    "localhost"
                ]
            ],
            "log": [
                "loglevel": "info"
            ],
            "inbounds": [
                [
                    "tag": "socks-in",
                    "port": socksPort,
                    "listen": listenAddress,
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
                    "listen": listenAddress,
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

        // 配置 security 层（streamSecurity 优先，兼容旧数据无此字段时回退到 security）
        let transportSecurity = !node.streamSecurity.isEmpty ? node.streamSecurity : node.security
        if transportSecurity == "reality" {
            streamSettings["security"] = "reality"
            streamSettings["realitySettings"] = buildRealitySettings(for: node)
        } else if transportSecurity == "tls" {
            streamSettings["security"] = "tls"
            streamSettings["tlsSettings"] = buildTlsSettings(for: node)
        }

        // 配置传输层
        if node.network == "ws" {
            streamSettings["wsSettings"] = buildWsSettings(for: node)
        } else if node.network == "grpc" {
            streamSettings["grpcSettings"] = buildGrpcSettings(for: node)
        } else if node.network == "tcp" && transportSecurity != "reality" && (!node.headerHost.isEmpty || !node.headerPath.isEmpty) {
            // reality 节点的 headerHost 是伪装目标域名（用于 serverName），不是 HTTP 伪装头
            streamSettings["tcpSettings"] = buildTcpHttpSettings(for: node)
        }

        return streamSettings
    }

    private func buildRealitySettings(for node: ProxyNode) -> [String: Any] {
        var settings: [String: Any] = [
            "show": false,
            "fingerprint": node.fingerprint.isEmpty ? "chrome" : node.fingerprint
        ]

        // serverName: sni 优先，为空时回退到 headerHost
        let serverName = !node.sni.isEmpty ? node.sni : node.headerHost
        if !serverName.isEmpty {
            settings["serverName"] = serverName
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
            "allowInsecure": node.allowInsecure
        ]

        // SNI: sni 优先，为空时回退到 headerHost（CF 节点通常没有 sni 字段）
        let serverName = !node.sni.isEmpty ? node.sni : node.headerHost
        if !serverName.isEmpty {
            settings["serverName"] = serverName
        }

        if !node.fingerprint.isEmpty {
            settings["fingerprint"] = node.fingerprint
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
            settings["host"] = node.headerHost
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

    private func buildTcpHttpSettings(for node: ProxyNode) -> [String: Any] {
        var request: [String: Any] = [:]

        if !node.headerPath.isEmpty {
            request["path"] = [node.headerPath]
        }
        if !node.headerHost.isEmpty {
            request["headers"] = ["Host": [node.headerHost]]
        }

        var header: [String: Any] = ["type": "http"]
        if !request.isEmpty {
            header["request"] = request
        }

        return ["header": header]
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
