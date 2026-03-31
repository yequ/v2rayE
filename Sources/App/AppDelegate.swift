import AppKit
import Foundation
import Sparkle

extension Notification.Name {
    static let appUpdateStatusDidChange = Notification.Name("AppUpdateStatusDidChange")
}

struct AppUpdateStatus {
    let message: String
    let isTransient: Bool
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

    private override init() {
        super.init()
    }

    func start() {
        guard canUseUpdater else { return }

        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = automaticUpdateInterval
        if updater.allowsAutomaticUpdates {
            updater.automaticallyDownloadsUpdates = true
        }

        updaterController.startUpdater()

        // Sparkle 建议在启动 updater 后的下一次 runloop 中触发启动检查。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let updater = self.updaterController.updater
            guard updater.automaticallyChecksForUpdates else { return }

            self.postStatus(message: "正在后台检查更新...", isTransient: true)
            updater.checkForUpdatesInBackground()
            updater.resetUpdateCycle()
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

    private func postStatus(message: String, isTransient: Bool) {
        NotificationCenter.default.post(
            name: .appUpdateStatusDidChange,
            object: AppUpdateStatus(message: message, isTransient: isTransient)
        )
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        postStatus(message: "发现新版本 \(version)，正在准备下载...", isTransient: false)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        postStatus(message: "发现新版本 \(version)，正在后台下载...", isTransient: false)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        postStatus(message: "新版本 \(version) 已下载完成，稍后可安装", isTransient: false)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        postStatus(message: "更新下载失败：\(error.localizedDescription)", isTransient: false)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        postStatus(message: "已取消更新下载", isTransient: true)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
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
