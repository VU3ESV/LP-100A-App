import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        VStack(spacing: 14) {
            StatusBar(state: vm.connection)

            MeterCase {
                LCDSurface {
                    VStack(spacing: 0) {
                        screenHead
                        Spacer().frame(height: 12)
                        activeView
                        Spacer().frame(minHeight: 16)
                        DashedDivider()
                        Spacer().frame(height: 12)
                        screenFoot
                    }
                }
                .frame(minHeight: 320)

                Spacer().frame(height: 16)
                KeypadView(vm: vm)
            }

            if let banner = vm.statusBanner {
                Text(banner)
                    .font(.system(size: 11))
                    .foregroundColor(Tokens.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Tokens.yellow.opacity(0.08))
                    )
            }
        }
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 24, trailing: 16))
        .frame(maxWidth: 760, maxHeight: .infinity)
        .frame(minWidth: 720, minHeight: 560)
        .background(backgroundGradient.ignoresSafeArea())
    }

    private var backgroundGradient: some View {
        RadialGradient(
            colors: [Color(hex: 0x1c232b), Color(hex: 0x0b0e12), Color(hex: 0x07090c)],
            center: .top,
            startRadius: 0,
            endRadius: 800
        )
    }

    private var screenHead: some View {
        HStack {
            Text("LP-100A · \(titleForCurrentView)".uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(Tokens.accent)
            Spacer()
            Text((vm.snapshot?.callsign.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "—"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Tokens.swrFg)
        }
    }

    private var titleForCurrentView: String {
        if vm.setupOpen { return "SETUP" }
        switch vm.currentView {
        case "normal": return "NORMAL"
        case "vector": return "VECTOR Z"
        default: return vm.currentView.uppercased()
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

    private var screenFoot: some View {
        HStack(spacing: 14) {
            PillView(label: "Mode", value: titleForCurrentView)
            PillView(
                label: "Setup",
                value: vm.setupOpen ? "Exit" : "Open",
                onTap: { vm.toggleSetup() }
            )
            PillView(label: "Pwr",
                     value: (vm.snapshot?.mode.rawValue.replacingOccurrences(of: "_", with: " ")) ?? "—")
            PillView(label: "Range",
                     value: vm.snapshot?.range.rawValue ?? "—")
            PillView(label: "Alarm",
                     value: vm.snapshot?.alarmSetpoint.rawValue ?? "off",
                     valueColor: vm.snapshot?.alarmTripped == true ? Tokens.red : Tokens.accent,
                     alarm: vm.snapshot?.alarmTripped == true,
                     blinking: vm.snapshot?.alarmTripped == true)
            Spacer()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
