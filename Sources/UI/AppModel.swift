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
    @Published var appVersion: String
    @Published var updateStatusMessage: String?
    private var hasHandledLaunchAutoConnect = false
    private var applicationWillTerminateObserver: NSObjectProtocol?
    private var updateStatusObserver: NSObjectProtocol?
    private var updateStatusClearWorkItem: DispatchWorkItem?
    private var pendingLaunchAutoConnectWorkItem: DispatchWorkItem?
    private var launchAutoConnectRetryIndex = 0
    private let latencyChecker = LatencyChecker()
    private let launchAutoConnectRetryDelays: [TimeInterval] = [1.5, 3.0, 5.0]

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
    private let updateController: AppUpdateController

    init(
        configStore: ConfigStore = ConfigStore(),
        subscriptionService: SubscriptionService = SubscriptionService(),
        configBuilder: V2RayConfigBuilder = V2RayConfigBuilder(),
        updateController: AppUpdateController? = nil
    ) {
        self.configStore = configStore
        self.subscriptionService = subscriptionService
        self.configBuilder = configBuilder
        self.updateController = updateController ?? .shared
        self.coreRunner = CoreRunner(configStore: configStore)
        self.config = configStore.load()
        self.status = CoreStatus(state: .disconnected, message: "未连接")
        self.coreExecutablePath = configStore.discoverCoreExecutableURL()?.path ?? "-"
        self.appVersion = Self.makeVersionString()
        self.pacServerAddress = pacServer.pacURLString
        self.applicationWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationWillTerminate()
            }
        }
        self.updateStatusObserver = NotificationCenter.default.addObserver(
            forName: .appUpdateStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let status = notification.object as? AppUpdateStatus else { return }
            Task { @MainActor [weak self] in
                self?.handleUpdateStatus(status)
            }
        }

        // 应用启动时检查是否需要自动连接
        performAutoConnectIfNeeded()
    }

    deinit {
        if let observer = applicationWillTerminateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = updateStatusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        updateStatusClearWorkItem?.cancel()
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
        cancelLaunchAutoConnectRetry(resetRetryState: true)
        connect(triggeredByLaunchAutoConnectRetry: false)
    }

    private func connect(triggeredByLaunchAutoConnectRetry: Bool) {
        guard let node = selectedNode else {
            status = CoreStatus(state: .failed, message: "请选择节点")
            return
        }

        if node.proxyProtocol == .vless,
           configStore.discoverCoreType() != .xray {
            handleConnectionFailure(
                message: "当前节点为 VLESS/Reality，需使用 Xray 内核。请安装 xray，或打包时内置 xray 后再连接。",
                triggeredByLaunchAutoConnectRetry: triggeredByLaunchAutoConnectRetry
            )
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
            handleConnectionFailure(
                message: "设置系统代理失败：\(error.localizedDescription)",
                triggeredByLaunchAutoConnectRetry: triggeredByLaunchAutoConnectRetry
            )
            return
        }

        // PAC 模式检查 proxy.js 文件
        if config.proxyMode == .pac {
            guard FileManager.default.fileExists(atPath: pacFileURL.path) else {
                handleConnectionFailure(
                    message: "PAC 文件不存在：\(pacFileURL.path)",
                    triggeredByLaunchAutoConnectRetry: triggeredByLaunchAutoConnectRetry
                )
                return
            }

            do {
                try pacServer.start()
            } catch {
                handleConnectionFailure(
                    message: "PAC 服务启动失败：\(error.localizedDescription)",
                    triggeredByLaunchAutoConnectRetry: triggeredByLaunchAutoConnectRetry
                )
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
        let listenAddress = self.config.proxyBindScope.listenAddress
        let nodeName = node.name

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let configData = try configBuilder.build(
                    for: node,
                    socksPort: socksPort,
                    httpPort: httpPort,
                    listenAddress: listenAddress,
                    proxyMode: proxyMode
                )
                let url = try configStore.saveGeneratedCoreConfig(configData)
                try coreRunner.start(with: url)

                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.async {
                    if coreRunner.isRunning {
                        self.cancelLaunchAutoConnectRetry(resetRetryState: true)
                        self.status = CoreStatus(state: .connected, message: "已连接：\(nodeName)")
                    } else {
                        self.handleConnectionFailure(
                            message: "v2ray 启动失败，请检查节点配置和内核文件",
                            triggeredByLaunchAutoConnectRetry: triggeredByLaunchAutoConnectRetry
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.handleConnectionFailure(
                        message: error.localizedDescription,
                        triggeredByLaunchAutoConnectRetry: triggeredByLaunchAutoConnectRetry
                    )
                }
            }
        }
    }

    func disconnect() {
        cancelLaunchAutoConnectRetry(resetRetryState: true)
        cleanupConnectionRuntimeState()
        status = CoreStatus(state: .disconnected, message: "已断开")
    }

    func checkForUpdates() {
        updateController.checkForUpdates()
    }

    func quitApp() {
        cleanupBeforeTermination()
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

    func updatePorts(httpPort: Int, socksPort: Int, proxyBindScope: ProxyBindScope) {
        config.httpPort = httpPort
        config.socksPort = socksPort
        config.proxyBindScope = proxyBindScope
        persistConfig()
        status = CoreStatus(
            state: .disconnected,
            message: "代理已更新：\(proxyBindScope.displayName)，HTTP \(httpPort)，SOCKS5 \(socksPort)"
        )
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

        launchAutoConnectRetryIndex = 0
        scheduleLaunchAutoConnectRetry(reason: "应用启动后正在恢复连接...")
    }

    private func scheduleLaunchAutoConnectRetry(reason: String) {
        guard launchAutoConnectRetryIndex < launchAutoConnectRetryDelays.count else {
            cancelLaunchAutoConnectRetry(resetRetryState: true)
            status = CoreStatus(state: .failed, message: "自动连接失败，请稍后再试")
            return
        }

        let delay = launchAutoConnectRetryDelays[launchAutoConnectRetryIndex]
        launchAutoConnectRetryIndex += 1
        pendingLaunchAutoConnectWorkItem?.cancel()
        status = CoreStatus(state: .connecting, message: reason)

        let workItem = DispatchWorkItem { [weak self] in
            self?.connect(triggeredByLaunchAutoConnectRetry: true)
        }
        pendingLaunchAutoConnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelLaunchAutoConnectRetry(resetRetryState: Bool) {
        pendingLaunchAutoConnectWorkItem?.cancel()
        pendingLaunchAutoConnectWorkItem = nil

        if resetRetryState {
            launchAutoConnectRetryIndex = 0
        }
    }

    private func handleConnectionFailure(message: String, triggeredByLaunchAutoConnectRetry: Bool) {
        cleanupConnectionRuntimeState()

        if triggeredByLaunchAutoConnectRetry,
           launchAutoConnectRetryIndex < launchAutoConnectRetryDelays.count {
            scheduleLaunchAutoConnectRetry(reason: "升级重启后内核仍在恢复，正在自动重试...")
            return
        }

        cancelLaunchAutoConnectRetry(resetRetryState: true)
        status = CoreStatus(state: .failed, message: message)
    }

    private func handleUpdateStatus(_ status: AppUpdateStatus) {
        updateStatusClearWorkItem?.cancel()
        updateStatusMessage = status.message

        guard status.isTransient else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.updateStatusMessage == status.message else { return }
            self?.updateStatusMessage = nil
        }
        updateStatusClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func handleApplicationWillTerminate() {
        cleanupBeforeTermination()
    }

    private func cleanupBeforeTermination() {
        cancelLaunchAutoConnectRetry(resetRetryState: true)
        cleanupConnectionRuntimeState()
    }

    private func cleanupConnectionRuntimeState() {
        coreRunner.stop()
        pacServer.stop()
        latencyChecker.stopMonitoring()
        latency = -1

        do {
            try systemProxyManager.disableWebProxy()
            try systemProxyManager.disableSOCKSProxy()
            try systemProxyManager.disableAutoProxy()
        } catch {
            // 静默处理清理错误，不中断当前流程
        }
    }

    private func persistConfig() {
        try? configStore.save(config)
    }

    private static func makeVersionString() -> String {
        let shortVersion = versionValue(for: "CFBundleShortVersionString")
        let buildVersion = versionValue(for: "CFBundleVersion")

        switch (shortVersion, buildVersion) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "v\(short) (\(build))"
        case let (short?, _):
            return "v\(short)"
        case let (_, build?):
            return "build \(build)"
        default:
            return "-"
        }
    }

    private static func versionValue(for key: String) -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        for infoURL in fallbackInfoPlistURLs {
            guard let data = try? Data(contentsOf: infoURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let value = plist[key] as? String else {
                continue
            }

            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        return nil
    }

    private static var fallbackInfoPlistURLs: [URL] {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let resourceInfoURL = projectRootURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Info.plist")

        return [resourceInfoURL]
    }
}
