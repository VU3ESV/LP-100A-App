import SwiftUI

// Compact glance shown in NSStatusBar. Mirrors the topbar pill plus a
// short power/SWR readout. Clicking opens a popover with a fuller block.
struct MenuBarLabel: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        let dot: String = {
            switch vm.connection {
            case .connected: return "●"
            case .reconnecting: return "◐"
            case .disconnected: return "○"
            }
        }()
        let pwr = vm.snapshot.map { formatPower($0.powerW) } ?? "—"
        let swr = vm.snapshot.map { String(format: "%.2f", $0.swr) } ?? "—"
        Text("\(dot) \(pwr) · \(swr)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private func formatPower(_ w: Double) -> String {
        if w >= 1000 { return String(format: "%.1fkW", w / 1000.0) }
        return String(format: "%.0fW", w)
    }
}

struct MenuBarContent: View {
    @ObservedObject var vm: MeterViewModel
    var onShowMain: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("PWR", value: vm.snapshot.map { String(format: "%.1f \(PowerModeSuffix.suffix(for: $0.mode))", $0.powerW) } ?? "—")
            row("SWR", value: vm.snapshot.map { String(format: "%.2f", $0.swr) } ?? "—")
            row("Range", value: vm.snapshot?.range.rawValue ?? "—")
            row("Mode", value: vm.snapshot?.mode.rawValue.replacingOccurrences(of: "_", with: " ") ?? "—")
            row("Alarm", value: vm.snapshot?.alarmSetpoint.rawValue ?? "off")
            Divider()
            Button("Show LP-100A Window") { onShowMain() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("Quit") { onQuit() }
                .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(8)
        .frame(width: 200)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
        .font(.system(size: 12))
    }
}
