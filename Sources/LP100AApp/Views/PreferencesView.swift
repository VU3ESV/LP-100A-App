import SwiftUI

struct PreferencesView: View {
    @ObservedObject var vm: MeterViewModel
    @AppStorage("alarmNotifications", store: AppDefaults.store) var alarmNotifications: Bool = true
    @AppStorage("menuBarItemEnabled", store: AppDefaults.store) var menuBarItemEnabled: Bool = true

    var body: some View {
        TabView {
            serverTab
                .tabItem { Label("Server", systemImage: "network") }
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
            displayTab
                .tabItem { Label("Display", systemImage: "display") }
        }
        .frame(width: 480, height: 280)
    }

    private var serverTab: some View {
        Form {
            LabeledContent("Server URL") {
                Text(vm.serverURLString.isEmpty ? "Not configured" : vm.serverURLString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(vm.serverURLString.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            LabeledContent("Status") {
                statusBadge
            }

            HStack {
                Button("Change Server…") {
                    vm.connectionSheetOpen = true
                }
                .controlSize(.regular)

                if vm.connection == .connected {
                    Button("Disconnect") {
                        Task { await vm.disconnect() }
                    }
                } else if vm.hasConfiguredServer {
                    Button("Reconnect") {
                        if let url = URL(string: vm.serverURLString) {
                            Task { await vm.reconnect(serverURL: url) }
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch vm.connection {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .reconnecting:
            Label("Reconnecting…", systemImage: "arrow.clockwise.circle.fill")
                .foregroundStyle(.yellow)
        case .disconnected:
            Label("Offline", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var notificationsTab: some View {
        Form {
            Toggle("Notify when SWR alarm trips", isOn: $alarmNotifications)
            Text("macOS notification posted on rising edge. Throttled to one per 30 s.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var displayTab: some View {
        Form {
            Toggle("Show menu-bar live readout", isOn: $menuBarItemEnabled)
            Text("Restart the app to apply menu-bar visibility changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
