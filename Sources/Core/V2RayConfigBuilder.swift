import Foundation

final class V2RayConfigBuilder {
    func build(for node: ProxyNode, socksPort: Int, httpPort: Int, proxyMode: ProxyMode) throws -> Data {
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
                [
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
                    ],
                    "streamSettings": [
                        "network": node.network
                    ]
                ],
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
