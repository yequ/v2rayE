import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig
    @Published var status: CoreStatus
    @Published var isBusy = false
    @Published var draftSubscriptionName = ""
    @Published var draftSubscriptionURL = ""
    @Published var coreExecutablePath: String = "-"
    @Published var pacServerAddress: String = "-"
    @Published var latency: Int = -1
    private var hasHandledLaunchAutoConnect = false
    private let latencyChecker = LatencyChecker()

    private let configStore: ConfigStore
    private let subscriptionService: SubscriptionService
    private let configBuilder: V2RayConfigBuilder
    private let coreRunner: CoreRunner
    private let pacFileURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first!
    .appendingPathComponent("v2rayE", isDirectory: true)
    .appendingPathComponent("proxy.js")
    private lazy var pacServer = PACServer(pacFileURL: pacFileURL)
    private let systemProxyManager = SystemProxyManager()

    init(
        configStore: ConfigStore = ConfigStore(),
        subscriptionService: SubscriptionService = SubscriptionService(),
        configBuilder: V2RayConfigBuilder = V2RayConfigBuilder()
    ) {
        self.configStore = configStore
        self.subscriptionService = subscriptionService
        self.configBuilder = configBuilder
        self.coreRunner = CoreRunner(configStore: configStore)
        self.config = configStore.load()
        self.status = CoreStatus(state: .disconnected, message: "未连接")
        self.coreExecutablePath = configStore.discoverCoreExecutableURL()?.path ?? "-"
        self.pacServerAddress = pacServer.pacURLString
        
        // 应用启动时检查是否需要自动连接
        performAutoConnectIfNeeded()
    }

    var statusText: String {
        status.message
    }

    var selectedSubscription: SubscriptionProfile? {
        config.subscriptions.first(where: { $0.id == config.selectedSubscriptionID })
    }

    var selectedNode: ProxyNode? {
        selectedSubscription?.nodes.first(where: { $0.id == config.selectedNodeID })
    }

    var statusItemSystemImageName: String {
        switch status.state {
        case .connected:
            return "lock.shield.fill"
        case .connecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "lock.open.fill"
        }
    }

    func addSubscription() {
        let name = draftSubscriptionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = draftSubscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else {
            status = CoreStatus(state: .failed, message: "订阅名称和链接不能为空")
            return
        }

        let profile = SubscriptionProfile(name: name, url: url)
        config.subscriptions.append(profile)
        config.selectedSubscriptionID = profile.id
        draftSubscriptionName = ""
        draftSubscriptionURL = ""
        persistConfig()
        status = CoreStatus(state: .disconnected, message: "已添加订阅：\(name)")
    }

    func refreshSelectedSubscription() async {
        guard let index = config.subscriptions.firstIndex(where: { $0.id == config.selectedSubscriptionID }) else {
            status = CoreStatus(state: .failed, message: "请先选择订阅")
            return
        }

        isBusy = true
        status = CoreStatus(state: .connecting, message: "正在更新订阅...")
        defer { isBusy = false }

        do {
            let updated = try await subscriptionService.refresh(profile: config.subscriptions[index])
            config.subscriptions[index] = updated
            config.selectedNodeID = updated.nodes.first?.id
            persistConfig()
            status = CoreStatus(state: .disconnected, message: "订阅已更新，共 \(updated.nodes.count) 个节点")
        } catch {
            status = CoreStatus(state: .failed, message: error.localizedDescription)
        }
    }

    func connect() {
        guard let node = selectedNode else {
            status = CoreStatus(state: .failed, message: "请选择节点")
            return
        }

        // 设置系统代理
        do {
            if config.proxyMode == .pac {
                try systemProxyManager.setPACURL(pacServer.pacURLString)
            } else {
                try systemProxyManager.setHTTPProxy(host: "127.0.0.1", port: config.httpPort)
                try systemProxyManager.setSOCKSProxy(host: "127.0.0.1", port: config.socksPort)
            }
        } catch {
            status = CoreStatus(state: .failed, message: "设置系统代理失败：\(error.localizedDescription)")
            return
        }

        // PAC 模式检查 proxy.js 文件
        if config.proxyMode == .pac {
            guard FileManager.default.fileExists(atPath: pacFileURL.path) else {
                status = CoreStatus(state: .failed, message: "PAC 文件不存在：\(pacFileURL.path)")
                return
            }

            do {
                try pacServer.start()
            } catch {
                status = CoreStatus(state: .failed, message: "PAC 服务启动失败：\(error.localizedDescription)")
                return
            }
        } else {
            pacServer.stop()
        }

        // 启动延迟检测
        latency = -1
        latencyChecker.onLatencyUpdate = { [weak self] latency in
            self?.latency = latency
        }
        latencyChecker.startMonitoring(interval: 3.0)

        status = CoreStatus(state: .connecting, message: "正在启动 v2ray...")

        // 捕获需要的值，避免在后台线程中访问 main actor 属性
        let configBuilder = self.configBuilder
        let configStore = self.configStore
        let coreRunner = self.coreRunner
        let socksPort = self.config.socksPort
        let httpPort = self.config.httpPort
        let proxyMode = self.config.proxyMode
        let nodeName = node.name

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let configData = try configBuilder.build(
                    for: node,
                    socksPort: socksPort,
                    httpPort: httpPort,
                    proxyMode: proxyMode
                )
                let url = try configStore.saveGeneratedCoreConfig(configData)
                try coreRunner.start(with: url)

                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.async {
                    if coreRunner.isRunning {
                        self.status = CoreStatus(state: .connected, message: "已连接：\(nodeName)")
                    } else {
                        self.status = CoreStatus(state: .failed, message: "v2ray 启动失败，请检查节点配置和内核文件")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = CoreStatus(state: .failed, message: error.localizedDescription)
                }
            }
        }
    }

    func disconnect() {
        coreRunner.stop()
        pacServer.stop()
        latencyChecker.stopMonitoring()
        latency = -1
        
        do {
            try systemProxyManager.disableWebProxy()
            try systemProxyManager.disableSOCKSProxy()
            try systemProxyManager.disableAutoProxy()
        } catch {
            status = CoreStatus(state: .failed, message: "清理系统代理失败：\(error.localizedDescription)")
            return
        }
        
        status = CoreStatus(state: .disconnected, message: "已断开")
    }

    func quitApp() {
        coreRunner.stop()
        pacServer.stop()
        latencyChecker.stopMonitoring()
        
        do {
            try systemProxyManager.disableWebProxy()
            try systemProxyManager.disableSOCKSProxy()
            try systemProxyManager.disableAutoProxy()
        } catch {
            // 静默处理清理错误，不中断退出
        }
        
        NSApp.terminate(nil)
    }

    func selectSubscription(_ id: UUID) {
        config.selectedSubscriptionID = id
        config.selectedNodeID = selectedSubscription?.nodes.first?.id
        persistConfig()
        if let name = selectedSubscription?.name {
            status = CoreStatus(state: .disconnected, message: "已选择订阅：\(name)")
        }
    }

    func selectNode(_ id: UUID) {
        config.selectedNodeID = id
        persistConfig()
        if let name = selectedNode?.name {
            status = CoreStatus(state: .disconnected, message: "已选择节点：\(name)")
        }
        // 如果当前已连接，立即重新连接以生效
        if coreRunner.isRunning {
            disconnect()
            connect()
        }
    }

    func updatePorts(httpPort: Int, socksPort: Int) {
        config.httpPort = httpPort
        config.socksPort = socksPort
        persistConfig()
        status = CoreStatus(state: .disconnected, message: "端口已更新：HTTP \(httpPort)，SOCKS5 \(socksPort)")
        if coreRunner.isRunning {
            disconnect()
            connect()
        }
    }

    func updateProxyMode(_ proxyMode: ProxyMode) {
        config.proxyMode = proxyMode
        if proxyMode != .pac {
            pacServer.stop()
        }
        persistConfig()
        status = CoreStatus(state: .disconnected, message: "已切换到 \(proxyMode.displayName) 模式")
        if coreRunner.isRunning {
            disconnect()
            connect()
        }
    }

    func updateAutoConnectOnLaunch(_ enabled: Bool) {
        config.autoConnectOnLaunch = enabled
        persistConfig()
        status = CoreStatus(state: .disconnected, message: enabled ? "已开启启动后自动连接" : "已关闭启动后自动连接")
    }

    private func performAutoConnectIfNeeded() {
        guard !hasHandledLaunchAutoConnect else { return }
        hasHandledLaunchAutoConnect = true
        guard config.autoConnectOnLaunch else { return }
        guard selectedNode != nil else { return }
        
        // 延遅执行，确保安全
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.connect()
        }
    }

    private func persistConfig() {
        try? configStore.save(config)
    }
}
