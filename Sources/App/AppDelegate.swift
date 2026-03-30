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
        guard isConfigured else { return }
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        guard isConfigured else {
            showMissingConfigurationAlert()
            return
        }
        updaterController.checkForUpdates(nil)
    }

    private var isConfigured: Bool {
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        return isValidSparkleValue(feedURL) && isValidSparkleValue(publicKey)
    }

    private func isValidSparkleValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedValue.isEmpty && !trimmedValue.hasPrefix("REPLACE_WITH_")
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
