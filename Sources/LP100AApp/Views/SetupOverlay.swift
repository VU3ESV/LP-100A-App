import SwiftUI

// SETUP overlay: re-alignment picker, log-level picker, and read-only
// reference cards from the LP-100A Quick Start Guide. The card LCD lines
// are rendered in their native green-on-black look (that's what they look
// like on the meter); everything around them is system-styled.
struct SetupOverlay: View {
    @ObservedObject var vm: MeterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            modeSyncBox
            logLevelBox
            banner
            cardsGrid
        }
    }

    private var modeSyncBox: some View {
        SectionBox(title: "Re-align with meter",
                   help: "The Mode button advances the meter's LCD AND the app together. If they drift after a restart, tell the app what the meter is actually showing now.") {
            HStack(spacing: 8) {
                ForEach(Array(vm.views.enumerated()), id: \.offset) { idx, v in
                    PickerChip(
                        label: viewLabel(v),
                        active: idx == vm.viewIdx,
                        action: { vm.setView(idx) }
                    )
                }
            }
        }
    }

    private var logLevelBox: some View {
        SectionBox(title: "Server log level",
                   help: "Change verbosity of the server's journal output at runtime. Setting is in-memory and resets on restart.") {
            HStack(spacing: 8) {
                ForEach(["error", "warn", "info", "debug"], id: \.self) { level in
                    PickerChip(
                        label: level,
                        active: level == vm.serverLogLevel,
                        action: { Task { await vm.setLogLevel(level) } }
                    )
                }
            }
        }
    }

    private var banner: some View {
        Label {
            Text("Read-only reference for the meter's SETUP screens. The serial protocol exposes only A / M / F / P; there's no remote-setup command. To change any of these, press & hold Mode on the physical meter for ≈1 s.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var cardsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 280), spacing: 12)]
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(Array(SetupScreens.all.enumerated()), id: \.offset) { i, s in
                    SetupCard(index: i + 1, total: SetupScreens.all.count, screen: s)
                }
            }
        }
        .frame(maxHeight: 480)
    }

    private func viewLabel(_ v: String) -> String {
        switch v {
        case "normal": return "Normal"
        case "vector": return "Vector Z"
        default: return v.capitalized
        }
    }
}

private struct SectionBox<Content: View>: View {
    var title: String
    var help: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

private struct PickerChip: View {
    var label: String
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.capitalized)
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.bordered)
        .tint(active ? .accentColor : .secondary)
    }
}

private struct SetupCard: View {
    var index: Int
    var total: Int
    var screen: SetupScreens.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(screen.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%02d / %02d", index, total))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(screen.lcd.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.26, green: 0.83, blue: 0.66))
                        .tracking(0.4)
                        .shadow(color: Color(red: 0.26, green: 0.83, blue: 0.66).opacity(0.3), radius: 2)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.85))
            )
            Text(screen.desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
