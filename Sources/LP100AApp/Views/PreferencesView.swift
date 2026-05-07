import SwiftUI

struct PreferencesView: View {
    @AppStorage("serverURL") var serverURL: String = "http://localhost:8088"
    @AppStorage("alarmNotifications") var alarmNotifications: Bool = true
    @AppStorage("menuBarItemEnabled") var menuBarItemEnabled: Bool = true
    @State private var testStatus: String = ""
    @State private var testInFlight: Bool = false

    var onChange: (URL) -> Void

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
            Section {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                Text("Default: http://localhost:8088 — point at your LP-100A server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Button("Apply") {
                        if let u = URL(string: serverURL) {
                            onChange(u)
                            testStatus = "Reconnecting…"
                        }
                    }
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if testInFlight { ProgressView().controlSize(.small) }
                        else { Text("Test connection") }
                    }
                    .disabled(testInFlight)
                    Spacer()
                    Text(testStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var notificationsTab: some View {
        Form {
            Toggle("Notify when SWR alarm trips", isOn: $alarmNotifications)
            Text("macOS notification posted on rising edge. Throttled to one per 30 s.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }

    private var displayTab: some View {
        Form {
            Toggle("Show menu-bar live readout", isOn: $menuBarItemEnabled)
            Text("Restart the app to apply menu-bar visibility changes.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }

    private func testConnection() async {
        guard let url = URL(string: serverURL) else {
            testStatus = "Invalid URL"
            return
        }
        testInFlight = true
        defer { testInFlight = false }
        let probe = url.appendingPathComponent("/healthz")
        do {
            let (_, resp) = try await URLSession.shared.data(from: probe)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                testStatus = "OK"
            } else {
                testStatus = "Server returned non-2xx"
            }
        } catch {
            testStatus = "Failed: \(error.localizedDescription)"
        }
    }
}
