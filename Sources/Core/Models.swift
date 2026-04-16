import Foundation

enum ProxyCoreType: String, Codable, CaseIterable, Identifiable {
    case xray
    case v2ray

    var id: String { rawValue }
}

enum ConnectionState: String, Codable {
    case disconnected
    case connecting
    case connected
    case failed
}

enum ProxyMode: String, Codable, CaseIterable, Identifiable {
    case global
    case pac

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .global:
            return "全局代理"
        case .pac:
            return "PAC"
        }
    }
}

enum ProxyBindScope: String, Codable, CaseIterable, Identifiable {
    case loopback
    case allInterfaces

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .loopback:
            return "仅本机"
        case .allInterfaces:
            return "允许外部"
        }
    }

    var listenAddress: String {
        switch self {
        case .loopback:
            return "127.0.0.1"
        case .allInterfaces:
            return "0.0.0.0"
        }
    }

    var description: String {
        switch self {
        case .loopback:
            return "仅本机可访问代理端口"
        case .allInterfaces:
            return "局域网设备可通过你的本机 IP 和端口访问代理"
        }
    }
}

enum ProxyProtocol: String, Codable {
    case vmess
    case vless
}

struct SubscriptionProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var url: String
    var lastUpdatedAt: Date?
    var nodes: [ProxyNode]

    init(id: UUID = UUID(), name: String, url: String, lastUpdatedAt: Date? = nil, nodes: [ProxyNode] = []) {
        self.id = id
        self.name = name
        self.url = url
        self.lastUpdatedAt = lastUpdatedAt
        self.nodes = nodes
    }
}

struct ProxyNode: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var address: String
    var port: Int
    var userId: String
    var alterId: Int
    var security: String
    var network: String
    var remark: String
    var proxyProtocol: ProxyProtocol
    // VLESS 特有参数
    var flow: String
    var sni: String
    var alpn: String
    var fingerprint: String
    var publicKey: String
    var headerHost: String
    var headerPath: String

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: Int,
        userId: String,
        alterId: Int = 0,
        security: String = "auto",
        network: String = "tcp",
        remark: String = "",
        proxyProtocol: ProxyProtocol = .vmess,
        flow: String = "",
        sni: String = "",
        alpn: String = "",
        fingerprint: String = "",
        publicKey: String = "",
        headerHost: String = "",
        headerPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.userId = userId
        self.alterId = alterId
        self.security = security
        self.network = network
        self.remark = remark
        self.proxyProtocol = proxyProtocol
        self.flow = flow
        self.sni = sni
        self.alpn = alpn
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.headerHost = headerHost
        self.headerPath = headerPath
    }
}

struct AppConfig: Codable {
    var subscriptions: [SubscriptionProfile]
    var selectedSubscriptionID: UUID?
    var selectedNodeID: UUID?
    var httpPort: Int
    var socksPort: Int
    var autoRefreshInterval: TimeInterval
    var proxyMode: ProxyMode
    var autoConnectOnLaunch: Bool
    var proxyBindScope: ProxyBindScope

    init(
        subscriptions: [SubscriptionProfile] = [],
        selectedSubscriptionID: UUID? = nil,
        selectedNodeID: UUID? = nil,
        httpPort: Int = 1087,
        socksPort: Int = 1080,
        autoRefreshInterval: TimeInterval = 3600,
        proxyMode: ProxyMode = .global,
        autoConnectOnLaunch: Bool = false,
        proxyBindScope: ProxyBindScope = .loopback
    ) {
        self.subscriptions = subscriptions
        self.selectedSubscriptionID = selectedSubscriptionID
        self.selectedNodeID = selectedNodeID
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.autoRefreshInterval = autoRefreshInterval
        self.proxyMode = proxyMode
        self.autoConnectOnLaunch = autoConnectOnLaunch
        self.proxyBindScope = proxyBindScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try container.decodeIfPresent([SubscriptionProfile].self, forKey: .subscriptions) ?? []
        selectedSubscriptionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSubscriptionID)
        selectedNodeID = try container.decodeIfPresent(UUID.self, forKey: .selectedNodeID)
        httpPort = try container.decodeIfPresent(Int.self, forKey: .httpPort) ?? 1087
        socksPort = try container.decodeIfPresent(Int.self, forKey: .socksPort) ?? 1080
        autoRefreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .autoRefreshInterval) ?? 3600
        proxyMode = try container.decodeIfPresent(ProxyMode.self, forKey: .proxyMode) ?? .global
        autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? false
        proxyBindScope = try container.decodeIfPresent(ProxyBindScope.self, forKey: .proxyBindScope) ?? .loopback
    }

    static let `default` = AppConfig()
}

struct CoreStatus {
    var state: ConnectionState
    var message: String
}
