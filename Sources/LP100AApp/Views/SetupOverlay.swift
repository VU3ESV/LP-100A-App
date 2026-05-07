import SwiftUI

// SETUP overlay: re-alignment picker, log-level picker, and the read-only
// reference cards from the LP-100A Quick Start Guide. Mirrors .view[data-view="setup"]
// in the web client; SETUP_SCREENS array ported verbatim.
struct SetupOverlay: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                modeSyncBox
                logLevelBox
                banner
                cardsGrid
            }
        }
    }

    private var modeSyncBox: some View {
        SyncBox(
            title: "Re-align web with meter",
            help: "The Mode button advances the meter's LCD AND the web display together. If they drift after a restart or someone presses the physical Mode button, tell the web what the meter is actually showing now:"
        ) {
            HStack(spacing: 8) {
                ForEach(Array(vm.views.enumerated()), id: \.offset) { idx, v in
                    PickerButton(
                        label: viewLabel(v),
                        active: idx == vm.viewIdx,
                        action: { vm.setView(idx) }
                    )
                }
            }
        }
    }

    private var logLevelBox: some View {
        SyncBox(
            title: "Server log level",
            help: "Change verbosity of the server's journal output at runtime. error is the quietest (default); debug includes a full per-frame trace. Setting is in-memory and resets on restart."
        ) {
            HStack(spacing: 8) {
                ForEach(["error", "warn", "info", "debug"], id: \.self) { level in
                    PickerButton(
                        label: level,
                        active: level == vm.serverLogLevel,
                        action: { Task { await vm.setLogLevel(level) } }
                    )
                }
            }
        }
    }

    private var banner: some View {
        Text("Below: read-only reference for the meter's SETUP screens. The serial protocol exposes only A / M / F / P; there's no remote-setup command. To change any of these, press & hold Mode on the physical meter for ≈1 s, then use Mode (next) / Alarm-Dn (lower) / Peak-Up (raise).")
            .font(.system(size: 11))
            .foregroundColor(Tokens.yellow)
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Tokens.yellow.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Tokens.yellow.opacity(0.3), lineWidth: 1)
                    )
            )
    }

    private var cardsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 280), spacing: 12)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(SetupScreens.all.enumerated()), id: \.offset) { i, s in
                SetupCard(index: i + 1, total: SetupScreens.all.count, screen: s)
            }
        }
    }

    private func viewLabel(_ v: String) -> String {
        switch v {
        case "normal": return "NORMAL"
        case "vector": return "VECTOR Z"
        default: return v.uppercased()
        }
    }
}

private struct SyncBox<Content: View>: View {
    var title: String
    var help: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(Tokens.accent)
            Text(help)
                .font(.system(size: 12))
                .foregroundColor(Tokens.label)
                .lineSpacing(2)
            content()
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Tokens.accent.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Tokens.dashed, lineWidth: 1)
                )
        )
    }
}

private struct PickerButton: View {
    var label: String
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(active ? Tokens.accent : Tokens.swrFg)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x1f262e), Color(hex: 0x131820)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(active ? Tokens.accent : Color(hex: 0x2a323c),
                                      lineWidth: 1)
                )
                .shadow(color: active ? Tokens.accent.opacity(0.25) : .clear, radius: 4)
        )
        .buttonStyle(.plain)
    }
}

private struct SetupCard: View {
    var index: Int
    var total: Int
    var screen: SetupScreens.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text(String(format: "%02d / %02d", index, total))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Tokens.tick)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(screen.lcd.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: 0x43d4a8))
                        .tracking(0.4)
                        .shadow(color: Color(hex: 0x43d4a8).opacity(0.3), radius: 2)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0x050708))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color(hex: 0x0e1218), lineWidth: 1)
                    )
            )
            Text(screen.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Tokens.swrFg)
                .tracking(0.6)
            Text(screen.desc)
                .font(.system(size: 11))
                .foregroundColor(Tokens.label)
                .lineSpacing(2)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 12, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: 0x0a0e12).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Tokens.dashed, lineWidth: 1)
                )
        )
    }
}
