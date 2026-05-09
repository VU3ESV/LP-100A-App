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
        .frame(minWidth: 820)
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
        VStack(spacing: 10) {
            if let banner = vm.statusBanner {
                BannerLabel(text: banner)
            }

            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    PanelHeader(
                        title: vm.setupOpen ? "Setup reference" : sectionTitle,
                        trailing: callsignAccessory
                    )
                    activeView
                }
            }

            CompactPanel {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        statusItem(label: "Range",
                                   value: vm.snapshot?.range.rawValue.capitalized ?? "—")
                        Spacer(minLength: 4)
                        statusItem(label: "Mode",
                                   value: vm.snapshot?.mode.rawValue.replacingOccurrences(of: "_", with: " ").capitalized ?? "—")
                        Spacer(minLength: 4)
                        statusItem(label: "Alarm",
                                   value: vm.snapshot?.alarmSetpoint.rawValue ?? "off",
                                   tint: (vm.snapshot?.alarmTripped == true) ? .red : .primary)
                        Spacer(minLength: 4)
                        statusItem(label: "Link",
                                   value: linkLabel,
                                   tint: linkTint)
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 22)
                    KeypadView(vm: vm)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var linkLabel: String {
        switch vm.connection {
        case .connected: return "Live"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Offline"
        }
    }

    private var linkTint: Color {
        switch vm.connection {
        case .connected: return .green
        case .reconnecting: return .yellow
        case .disconnected: return .red
        }
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
        } else {
            NormalView(snapshot: vm.snapshot, peakPwr: vm.peakPwr, peakSwr: vm.peakSwr)
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

    private func statusItem(label: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tint)
                .monospacedDigit()
                .lineLimit(1)
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

// Capsule pill row matching LP-700-App's BackendBadge styling. Two
// chips fully rounded (cornerRadius 999), tinted accent when active,
// muted otherwise. Tappable for direct view switching.
private struct ViewPicker: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(vm.views.enumerated()), id: \.offset) { idx, v in
                chip(label: label(for: v),
                     active: idx == vm.viewIdx && !vm.setupOpen,
                     icon: icon(for: v),
                     action: { vm.setView(idx) })
            }
        }
        .opacity(vm.setupOpen ? 0.4 : 1.0)
        .disabled(vm.setupOpen)
    }

    private func chip(label: String, active: Bool, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.06 * 11)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(active ? .accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(active ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .strokeBorder(active ? Color.accentColor.opacity(0.5)
                                          : Color.secondary.opacity(0.3),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func label(for v: String) -> String {
        switch v {
        case "normal": return "Normal"
        case "vector": return "Vector Z"
        default: return v.capitalized
        }
    }

    private func icon(for v: String) -> String {
        switch v {
        case "vector": return "scope"
        default: return "waveform"
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
