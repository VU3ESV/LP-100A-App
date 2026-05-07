import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: MeterViewModel
    @AppStorage("serverURL") private var persistedURL: String = ""

    var body: some View {
        Group {
            if vm.connectionSheetOpen || (!vm.hasConfiguredServer && persistedURL.isEmpty) {
                ConnectionPlaceholder(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                meterPane
            }
        }
        .navigationTitle("LP-100A")
        .toolbar { mainToolbar }
        .sheet(isPresented: $vm.connectionSheetOpen) {
            ConnectionSheet(vm: vm) { vm.connectionSheetOpen = false }
        }
        .frame(minWidth: 720, minHeight: 540)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ConnectionBadge(state: vm.connection, host: hostHint)
                .help(hostHint)
        }

        ToolbarItem(placement: .principal) {
            ViewPicker(vm: vm)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.connectionSheetOpen = true
            } label: {
                Image(systemName: "network.badge.shield.half.filled")
                    .help("Server connection settings")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.toggleSetup()
            } label: {
                Image(systemName: vm.setupOpen ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                    .help("Open SETUP reference")
            }
        }
    }

    private var hostHint: String {
        if let url = URL(string: vm.serverURLString), let host = url.host {
            let port = url.port.map { ":\($0)" } ?? ""
            return "\(host)\(port)"
        }
        return "Not configured"
    }

    // MARK: - Main pane

    private var meterPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let banner = vm.statusBanner {
                    BannerLabel(text: banner)
                }

                Panel {
                    VStack(alignment: .leading, spacing: 16) {
                        PanelHeader(
                            title: vm.setupOpen ? "Setup reference" : sectionTitle,
                            trailing: callsignAccessory
                        )

                        Divider()

                        activeView
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow
                        Divider()
                        KeypadView(vm: vm)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var sectionTitle: String {
        switch vm.currentView {
        case "vector": return "Vector impedance"
        default: return "Power & SWR"
        }
    }

    @ViewBuilder
    private var activeView: some View {
        if vm.setupOpen {
            SetupOverlay(vm: vm)
        } else if vm.currentView == "vector" {
            VectorView(snapshot: vm.snapshot)
                .frame(minHeight: 260)
        } else {
            NormalView(snapshot: vm.snapshot, peakPwr: vm.peakPwr, peakSwr: vm.peakSwr)
                .frame(minHeight: 200)
        }
    }

    private var callsignAccessory: AnyView? {
        let cs = vm.snapshot?.callsign.trimmingCharacters(in: .whitespaces) ?? ""
        guard !cs.isEmpty else { return nil }
        return AnyView(
            Text(cs)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        )
    }

    private var statusRow: some View {
        HStack(spacing: 18) {
            statusItem(label: "Power range",
                       value: vm.snapshot?.range.rawValue.capitalized ?? "—")
            statusItem(label: "Peak mode",
                       value: vm.snapshot?.mode.rawValue.replacingOccurrences(of: "_", with: " ").capitalized ?? "—")
            statusItem(label: "Alarm",
                       value: vm.snapshot?.alarmSetpoint.rawValue ?? "off",
                       tint: (vm.snapshot?.alarmTripped == true) ? .red : .primary)
            Spacer()
            if vm.connection != .connected {
                Label("Not connected", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusItem(label: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundColor(tint)
                .monospacedDigit()
        }
    }
}

// MARK: - Toolbar pieces

private struct ConnectionBadge: View {
    var state: WSClient.ConnectionState
    var host: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: state == .connected ? 3 : 0)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text(host)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .reconnecting: return .yellow
        case .disconnected: return .red
        }
    }

    private var label: String {
        switch state {
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Offline"
        }
    }
}

private struct ViewPicker: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        Picker("", selection: Binding(
            get: { vm.currentView },
            set: { newValue in
                if let idx = vm.views.firstIndex(of: newValue) {
                    vm.setView(idx)
                }
            }
        )) {
            ForEach(vm.views, id: \.self) { v in
                Text(label(for: v)).tag(v)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200)
        .disabled(vm.setupOpen)
    }

    private func label(for v: String) -> String {
        switch v {
        case "normal": return "Normal"
        case "vector": return "Vector Z"
        default: return v.capitalized
        }
    }
}

private struct BannerLabel: View {
    var text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.08))
            )
    }
}

// MARK: - First-launch placeholder

struct ConnectionPlaceholder: View {
    @ObservedObject var vm: MeterViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("No server connected")
                .font(.title2.weight(.semibold))
            Text("Configure the URL of your LP-100A WebSocket server to begin streaming telemetry.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                vm.connectionSheetOpen = true
            } label: {
                Text("Connect…").frame(minWidth: 100)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
