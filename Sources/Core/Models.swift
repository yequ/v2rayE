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
    var subscriptions: [SubscriptionProfile] = []
    var selectedSubscriptionID: UUID?
    var selectedNodeID: UUID?
    var httpPort: Int = 1087
    var socksPort: Int = 1080
    var autoRefreshInterval: TimeInterval = 3600
    var proxyMode: ProxyMode = .global
    var autoConnectOnLaunch: Bool = false

    static let `default` = AppConfig()
}

struct CoreStatus {
    var state: ConnectionState
    var message: String
}
