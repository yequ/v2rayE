import AppKit
import Sparkle

@MainActor
final class AppUpdateController {
    static let shared = AppUpdateController()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func start() {
        guard canUseUpdater else { return }
        updaterController.startUpdater()
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppUpdateController.shared.start()
    }
}
