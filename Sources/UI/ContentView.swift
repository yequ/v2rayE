import AppKit
import SwiftUI

private final class AddSubscriptionWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AddSubscriptionWindowController()

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "添加订阅"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace]
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(appModel: AppModel) {
        guard let panel = window as? NSPanel else { return }
        panel.contentView = NSHostingView(rootView: AddSubscriptionView(appModel: appModel))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
    }
}

private struct AddSubscriptionView: View {
    @ObservedObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加订阅")
                        .font(.title3.bold())
                    Text("填写名称和订阅链接后保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            modalInputField(title: "名称", text: $appModel.draftSubscriptionName)
            modalInputField(title: "链接", text: $appModel.draftSubscriptionURL)

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("保存") {
                    let trimmedName = appModel.draftSubscriptionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedURL = appModel.draftSubscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
                    appModel.addSubscription()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func modalInputField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var httpPortText = "1087"
    @State private var socksPortText = "1080"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            configGrid
            footerBar
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(backgroundGradient)
        .onAppear {
            httpPortText = String(appModel.config.httpPort)
            socksPortText = String(appModel.config.socksPort)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("v2rayE")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(appModel.appVersion)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appModel.checkForUpdates()
                } label: {
                    Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openAddSubscriptionWindow()
                } label: {
                    Label("添加订阅", systemImage: "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                statusIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.statusText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(color(for: appModel.status.state))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        compactChip(icon: "bolt.horizontal.circle", text: stateLabel(for: appModel.status.state))

                        if appModel.status.state == .connected && appModel.latency >= 0 {
                            compactChip(icon: "gauge.with.dots.needle.33percent", text: "\(appModel.latency) ms")
                        }
                    }

                    if let updateStatusMessage = appModel.updateStatusMessage {
                        Label(updateStatusMessage, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                iconCopyButton(text: appModel.statusText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
        }
        .padding(16)
        .background(cardBackground)
    }

    private var configGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                subscriptionCard
                nodeCard
                launchAndModeCard
            }

            VStack(spacing: 12) {
                coreCard
                portCard
            }
        }
    }

    private var subscriptionCard: some View {
        sectionCard(title: "订阅", systemImage: "tray.full.fill", tint: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                if appModel.config.subscriptions.isEmpty {
                    emptyState(text: "暂无订阅，点击右上角“添加订阅”", systemImage: "tray")
                } else {
                    HStack(spacing: 8) {
                        Picker("当前订阅", selection: Binding<UUID?>(
                            get: { appModel.config.selectedSubscriptionID },
                            set: { if let value = $0 { appModel.selectSubscription(value) } }
                        )) {
                            Text("选择订阅").tag(UUID?.none)
                            ForEach(appModel.config.subscriptions) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(appModel.isBusy ? "更新中..." : "刷新") {
                            Task {
                                await appModel.refreshSelectedSubscription()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(appModel.isBusy)
                    }

                    if let updatedAt = appModel.selectedSubscription?.lastUpdatedAt {
                        Label(updatedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var nodeCard: some View {
        sectionCard(title: "节点", systemImage: "network", tint: .teal) {
            VStack(alignment: .leading, spacing: 10) {
                if let nodes = appModel.selectedSubscription?.nodes, !nodes.isEmpty {
                    Picker("当前节点", selection: Binding<UUID?>(
                        get: { appModel.config.selectedNodeID },
                        set: { if let value = $0 { appModel.selectNode(value) } }
                    )) {
                        Text("选择节点").tag(UUID?.none)
                        ForEach(nodes) { node in
                            Text(node.name).tag(Optional(node.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                } else {
                    emptyState(text: "当前订阅还没有可用节点", systemImage: "wifi.exclamationmark")
                }
            }
        }
    }

    private var launchAndModeCard: some View {
        sectionCard(title: "连接设置", systemImage: "switch.2", tint: .purple) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("模式", selection: Binding(
                    get: { appModel.config.proxyMode },
                    set: { appModel.updateProxyMode($0) }
                )) {
                    ForEach(ProxyMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("启动后自动连接", isOn: Binding(
                    get: { appModel.config.autoConnectOnLaunch },
                    set: { appModel.updateAutoConnectOnLaunch($0) }
                ))
                .toggleStyle(.switch)
            }
        }
    }

    private var coreCard: some View {
        sectionCard(title: "内核与 PAC", systemImage: "cpu.fill", tint: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                compactInfoRow(title: "内核", value: appModel.coreExecutablePath, tint: .orange)

                if appModel.config.proxyMode == .pac {
                    compactInfoRow(title: "PAC", value: appModel.pacServerAddress, tint: .purple)
                }
            }
        }
    }

        private var portCard: some View {
        sectionCard(title: "端口", systemImage: "point.3.connected.trianglepath.dotted", tint: .pink) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    compactInputField("HTTP", text: $httpPortText)
                    compactInputField("SOCKS5", text: $socksPortText)
                }

                Button {
                    appModel.updatePorts(
                        httpPort: Int(httpPortText) ?? 1087,
                        socksPort: Int(socksPortText) ?? 1080
                    )
                } label: {
                    Label("保存端口", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue)
                )
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            toggleConnectionButton

            actionButton(title: "退出", systemImage: "power", tint: .red) {
                appModel.quitApp()
            }
        }
    }

    private var toggleConnectionButton: some View {
        actionButton(
            title: primaryActionTitle,
            systemImage: primaryActionIcon,
            tint: primaryActionTint
        ) {
            if appModel.status.state == .connected || appModel.status.state == .connecting {
                appModel.disconnect()
            } else {
                appModel.connect()
            }
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(color(for: appModel.status.state).opacity(0.15))
                .frame(width: 44, height: 44)
                .shadow(color: color(for: appModel.status.state).opacity(0.3), radius: 8, x: 0, y: 4)

            Image(systemName: iconName(for: appModel.status.state))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color(for: appModel.status.state))
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.blue.opacity(0.06),
                Color.purple.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func panelBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.09))
    }

    private func inputBackground(compact: Bool = true) -> some View {
        RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
            .fill(Color.black.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
    }

    private func sectionCard<Content: View>(title: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            content()
        }
        .padding(14)
        .background(cardBackground)
    }

    private func compactInputField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }

    private func compactInfoRow(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 36, alignment: .leading)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            iconCopyButton(text: value)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }

    private func emptyState(text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(inputBackground())
    }

    private func actionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: tint.opacity(0.3), radius: 6, x: 0, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func openAddSubscriptionWindow() {
        AddSubscriptionWindowController.shared.show(appModel: appModel)
    }

    private func iconCopyButton(text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var primaryActionTitle: String {
        switch appModel.status.state {
        case .connected:
            return "断开"
        case .connecting:
            return "取消连接"
        case .failed, .disconnected:
            return "连接"
        }
    }

    private var primaryActionIcon: String {
        switch appModel.status.state {
        case .connected:
            return "pause.fill"
        case .connecting:
            return "xmark.circle.fill"
        case .failed, .disconnected:
            return "bolt.fill"
        }
    }

    private var primaryActionTint: Color {
        switch appModel.status.state {
        case .connected:
            return .orange
        case .connecting:
            return .yellow
        case .failed, .disconnected:
            return .green
        }
    }

    private func stateLabel(for state: ConnectionState) -> String {
        switch state {
        case .connected:
            return "已连接"
        case .connecting:
            return "连接中"
        case .failed:
            return "失败"
        case .disconnected:
            return "未连接"
        }
    }

    private func iconName(for state: ConnectionState) -> String {
        switch state {
        case .connected:
            return "checkmark.seal.fill"
        case .connecting:
            return "bolt.horizontal.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "moon.zzz.fill"
        }
    }

    private func color(for state: ConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .failed:
            return .red
        case .disconnected:
            return .secondary
        }
    }
}
