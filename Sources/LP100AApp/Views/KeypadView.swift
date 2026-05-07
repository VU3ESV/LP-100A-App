import SwiftUI

struct KeypadView: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        HStack(spacing: 12) {
            keyButton(title: "Mode",
                      subtitle: viewSubtitle,
                      action: { vm.sendMode() })
                .keyboardShortcut("m", modifiers: [.command])

            keyButton(title: "Alarm Dn",
                      subtitle: "SWR setpoint",
                      action: { vm.sendAlarm() })
                .keyboardShortcut("a", modifiers: [.command])

            keyButton(title: "Peak / Avg / Tune",
                      subtitle: "Toggle (F)",
                      action: { vm.sendPeak() })
                .keyboardShortcut("p", modifiers: [.command])
        }
    }

    private var viewSubtitle: String {
        let v = vm.currentView
        switch v {
        case "normal": return "NORMAL"
        case "vector": return "VECTOR Z"
        default: return v.uppercased()
        }
    }

    private func keyButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        let disabled = vm.setupOpen || vm.connection != .connected || !vm.allowControl
        return Button(action: action) {
            VStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(Tokens.swrFg)
                Text(subtitle.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.1)
                    .foregroundColor(Tokens.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
        }
        .buttonStyle(KeyButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }
}

private struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x1f262e), Color(hex: 0x131820)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(hex: 0x2a323c), lineWidth: 1)
                    )
            )
            .offset(y: configuration.isPressed ? 1 : 0)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
    }
}
