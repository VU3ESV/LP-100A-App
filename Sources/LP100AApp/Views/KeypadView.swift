import SwiftUI

// Three control verbs the LP-100A serial protocol accepts. Compact
// bordered buttons matching LP-700-App's KeypadView footprint so the
// status row + keypad fit on a single CompactPanel without scrolling.
struct KeypadView: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        let disabled = !vm.allowControl || vm.connection != .connected || vm.setupOpen

        HStack(spacing: 10) {
            keyButton(title: "Mode",
                      systemImage: "rectangle.3.offgrid",
                      subtitle: viewSubtitle,
                      action: { vm.sendMode() })
                .keyboardShortcut("m", modifiers: [.command])

            keyButton(title: "Alarm",
                      systemImage: "bell.badge",
                      subtitle: vm.snapshot?.alarmSetpoint.rawValue ?? "—",
                      action: { vm.sendAlarm() })
                .keyboardShortcut("a", modifiers: [.command])

            keyButton(title: "Peak",
                      systemImage: "waveform.path",
                      subtitle: peakSubtitle,
                      action: { vm.sendPeak() })
                .keyboardShortcut("p", modifiers: [.command])

            keyButton(title: "Resync",
                      systemImage: "arrow.clockwise",
                      subtitle: "From server",
                      action: { vm.resync() })
                .keyboardShortcut("y", modifiers: [.command])

            if !vm.allowControl {
                Label("Read-only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(disabled)
    }

    private var viewSubtitle: String {
        switch vm.currentView {
        case "vector": return "Vector Z"
        default: return "Normal"
        }
    }

    private var peakSubtitle: String {
        guard let m = vm.snapshot?.mode else { return "—" }
        switch m {
        case .average: return "Average"
        case .peakHold: return "Peak Hold"
        case .tune: return "Tune"
        }
    }

    private func keyButton(title: String, systemImage: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
