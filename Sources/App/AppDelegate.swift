import AppKit
import Foundation
import Sparkle

extension Notification.Name {
    static let appUpdateStatusDidChange = Notification.Name("AppUpdateStatusDidChange")
}

struct AppUpdateStatus {
    let message: String
    let isTransient: Bool
    let isUpdateReady: Bool
    let readyUpdateVersion: String?

    init(message: String, isTransient: Bool, isUpdateReady: Bool = false, readyUpdateVersion: String? = nil) {
        self.message = message
        self.isTransient = isTransient
        self.isUpdateReady = isUpdateReady
        self.readyUpdateVersion = readyUpdateVersion
    }
}

@MainActor
final class AppUpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdateController()

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private let automaticUpdateInterval: TimeInterval = 24 * 60 * 60

    var isUpdateReady = false
    var readyUpdateVersion: String?
    private var foundUpdateItem: SUAppcastItem?

    private override init() {
        super.init()
    }

    func start() {
        guard canUseUpdater else { return }

        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = automaticUpdateInterval
        updater.automaticallyDownloadsUpdates = false

        updaterController.startUpdater()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let updater = self.updaterController.updater
            guard updater.automaticallyChecksForUpdates else { return }

            self.postStatus(message: "正在后台检查更新...", isTransient: true)
            updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard isRunningFromAppBundle else {
            showDebugRunAlert()
            return
        }
        guard isConfigured else {
            showMissingConfigurationAlert()
            return
        }
        updaterController.checkForUpdates(nil)
    }

    func downloadUpdate() {
        guard isRunningFromAppBundle, isConfigured else { return }
        guard foundUpdateItem != nil else {
            // 没有缓存的更新项，回退到手动检查
            checkForUpdates()
            return
        }

        let version = readyUpdateVersion ?? ""
        postStatus(message: "正在下载 v\(version)...", isTransient: false)

        let updater = updaterController.updater
        updater.automaticallyDownloadsUpdates = true
        updater.resetUpdateCycle()
        updater.checkForUpdatesInBackground()
    }

    private var canUseUpdater: Bool {
        isRunningFromAppBundle && isConfigured
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var isConfigured: Bool {
        let feedURL = sparkleConfigValue(for: "SUFeedURL")
        let publicKey = sparkleConfigValue(for: "SUPublicEDKey")

        return isValidSparkleValue(feedURL) && isValidSparkleValue(publicKey)
    }

    private func sparkleConfigValue(for key: String) -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           isValidSparkleValue(value) {
            return value
        }

        for infoURL in fallbackInfoPlistURLs {
            guard let data = try? Data(contentsOf: infoURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let value = plist[key] as? String,
                  isValidSparkleValue(value) else {
                continue
            }

            return value
        }

        return nil
    }

    private var fallbackInfoPlistURLs: [URL] {
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

    private func isValidSparkleValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedValue.isEmpty && !trimmedValue.hasPrefix("REPLACE_WITH_")
    }

    private func showDebugRunAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "调试运行模式下不可检查更新"
        alert.informativeText = "Sparkle 需要运行在正式的 .app bundle 中。请使用 build.sh 打包后的应用，或直接打开 dist/v2rayE.app 后再检查更新。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func showMissingConfigurationAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "自动更新尚未配置完成"
        alert.informativeText = "请先在应用配置中填入有效的 SUPublicEDKey，并发布可访问的 appcast.xml。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func postStatus(message: String, isTransient: Bool, isUpdateReady: Bool = false, readyUpdateVersion: String? = nil) {
        NotificationCenter.default.post(
            name: .appUpdateStatusDidChange,
            object: AppUpdateStatus(
                message: message,
                isTransient: isTransient,
                isUpdateReady: isUpdateReady,
                readyUpdateVersion: readyUpdateVersion
            )
        )
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        foundUpdateItem = item
        isUpdateReady = true
        readyUpdateVersion = version

        // 如果正在自动下载（用户点击了下载按钮），不覆盖下载状态消息
        if !updater.automaticallyDownloadsUpdates {
            postStatus(
                message: "发现新版本 v\(version)，点击下载更新",
                isTransient: false,
                isUpdateReady: true,
                readyUpdateVersion: version
            )
        }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        postStatus(message: "正在下载 v\(version)...", isTransient: false)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        isUpdateReady = true
        readyUpdateVersion = version
        postStatus(
            message: "v\(version) 已下载就绪，即将安装重启",
            isTransient: false,
            isUpdateReady: true,
            readyUpdateVersion: version
        )
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        isUpdateReady = true
        foundUpdateItem = item
        updater.automaticallyDownloadsUpdates = false
        postStatus(message: "下载失败，请重试：\(error.localizedDescription)", isTransient: false)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        isUpdateReady = true
        updater.automaticallyDownloadsUpdates = false
        postStatus(message: "下载已取消，点击按钮重新下载", isTransient: true)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        foundUpdateItem = nil
        let userInitiated = (error as NSError).userInfo["SPUNoUpdateFoundUserInitiatedKey"] as? Bool ?? false
        postStatus(message: userInitiated ? "当前已是最新版本" : "启动时已检查更新，当前已是最新版本", isTransient: true)
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        postStatus(message: "更新即将安装，应用将重新启动", isTransient: false)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppUpdateController.shared.start()
    }
}
