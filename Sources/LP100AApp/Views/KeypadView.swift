import SwiftUI

// The three control verbs the LP-100A's serial protocol accepts. Wrapped
// in native bordered buttons so they sit comfortably in the Mac toolbar
// idiom; functional, not decorative.
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
                      subtitle: "SWR setpoint",
                      action: { vm.sendAlarm() })
                .keyboardShortcut("a", modifiers: [.command])

            keyButton(title: "Peak / Avg / Tune",
                      systemImage: "waveform.path",
                      subtitle: peakSubtitle,
                      action: { vm.sendPeak() })
                .keyboardShortcut("p", modifiers: [.command])

            Spacer()

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
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.callout, design: .default).weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
