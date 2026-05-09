import SwiftUI

// Power & SWR readout panel modeled after LP-700-App's PowerSWRView. Two
// reading cards on top (Power + SWR), then a compact info row with dBW /
// dBm / Z / phase. The bargraph is a slim Capsule below the big numeric
// — color-thresholded so signal severity reads at a glance.
struct NormalView: View {
    var snapshot: Telemetry?
    var peakPwr: Double
    var peakSwr: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ReadingCard(label: "Power",
                            value: formatPower(snapshot?.powerW),
                            tint: .accentColor,
                            bar: powerBar)
                ReadingCard(label: "SWR",
                            value: (String(format: "%.2f", snapshot?.swr ?? 1.0), ""),
                            tint: swrTint(snapshot?.swr ?? 1.0),
                            bar: swrBar)
            }

            CompactPanel {
                HStack(spacing: 8) {
                    statusItem(label: "dBW", value: snapshot.map { String(format: "%.1f", $0.dbw) } ?? "—")
                    Spacer(minLength: 4)
                    statusItem(label: "dBm", value: snapshot.map { String(format: "%.1f", $0.dbm) } ?? "—")
                    Spacer(minLength: 4)
                    statusItem(label: "|Z|", value: snapshot.map { String(format: "%.1f Ω", $0.zOhm) } ?? "—")
                    Spacer(minLength: 4)
                    statusItem(label: "Phase", value: snapshot.map { String(format: "%.1f°", $0.phaseDeg) } ?? "—")
                    Spacer(minLength: 4)
                    statusItem(label: "Peak (W)",
                               value: peakPwr > 0 ? String(format: "%.1f", peakPwr) : "—")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Bar configs

    private var powerBar: ReadingCard.BarConfig {
        let scale = RangeScale.max(for: snapshot?.range ?? .high)
        let frac = (snapshot?.powerW ?? 0) / scale
        return ReadingCard.BarConfig(fraction: frac, scale: scale, baseTint: .cyan)
    }

    private var swrBar: ReadingCard.BarConfig {
        let swr = snapshot?.swr ?? 1.0
        let frac = (swr - 1.0) / (SWRScale.max - 1.0)
        return ReadingCard.BarConfig(fraction: frac, scale: SWRScale.max, baseTint: .green)
    }

    private func formatPower(_ w: Double?) -> (value: String, unit: String) {
        guard let w, !w.isNaN else { return ("—", "W") }
        let suffix = PowerModeSuffix.suffix(for: snapshot?.mode ?? .average)
        if w >= 1000 { return (String(format: "%.2f", w / 1000.0), "k\(suffix)") }
        if w >= 100  { return (String(format: "%.0f", w), suffix) }
        return (String(format: "%.1f", w), suffix)
    }

    private func swrTint(_ swr: Double) -> Color {
        if swr >= SWRScale.badThreshold { return .red }
        if swr >= SWRScale.warnThreshold { return .yellow }
        return .accentColor
    }

    private func statusItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

// MARK: - ReadingCard (the LP-700 visual signature)

struct ReadingCard: View {
    var label: String
    var value: (value: String, unit: String)
    var tint: Color
    var bar: BarConfig? = nil

    struct BarConfig {
        var fraction: Double
        var scale: Double
        var baseTint: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelHeader(title: label)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value.value)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(tint)
                if !value.unit.isEmpty {
                    Text(value.unit)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            if let bar {
                PowerBar(fraction: bar.fraction, baseTint: bar.baseTint)
                Text("0 / \(formatScale(bar.scale))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func formatScale(_ w: Double) -> String {
        if w >= 1000 { return String(format: "%g kW", w / 1000.0) }
        if abs(w - SWRScale.max) < 0.001 { return String(format: "%.1f", w) }
        return String(format: "%g W", w)
    }
}

private struct PowerBar: View {
    var fraction: Double
    var baseTint: Color

    var body: some View {
        let f = max(0, min(1, fraction))
        let color: Color = {
            if fraction >= 0.95 { return .red }
            if fraction >= 0.80 { return .yellow }
            return baseTint
        }()
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(color.gradient)
                    .frame(width: max(2, geo.size.width * f))
            }
        }
        .frame(height: 6)
    }
}
