import SwiftUI

@main
struct V2rayEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra("v2rayE", systemImage: appModel.statusItemSystemImageName) {
            ContentView()
                .environmentObject(appModel)
                .frame(width: 500, height: 640)
        }
        .menuBarExtraStyle(.window)
        Settings {
            EmptyView()
        }
    }
}
