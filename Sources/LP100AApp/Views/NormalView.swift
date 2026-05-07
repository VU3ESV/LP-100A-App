import SwiftUI

// Power & SWR readouts. The bargraph fills retain functional color
// (teal / yellow / red) but everything around them uses system colors so
// the panel feels native in light or dark mode.
struct NormalView: View {
    var snapshot: Telemetry?
    var peakPwr: Double
    var peakSwr: Double

    var body: some View {
        let d = snapshot
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 18) {
                pwrBar(d: d)
                swrBar(d: d)
            }
            Divider()
            readouts(d: d)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 240)
        }
    }

    private func pwrBar(d: Telemetry?) -> some View {
        let range = d?.range ?? .high
        let pwr = d?.powerW ?? 0
        let max = RangeScale.max(for: range)
        let frac = max > 0 ? pwr / max : 0
        let peakFrac = max > 0 ? peakPwr / max : 0
        let suffix = PowerModeSuffix.suffix(for: d?.mode ?? .average)
        let valueText = d.map { String(format: "%.1f \(suffix)", $0.powerW) } ?? "—"
        let scaleLabel = "\(range.rawValue.capitalized) · 0–\(Int(max)) W"

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Power")
                    .font(.subheadline.weight(.semibold))
                Text(scaleLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            BargraphView(
                fillFraction: frac,
                peakFraction: peakFrac,
                fillStyle: .normal,
                ticks: RangeScale.ticks(for: range)
            )
        }
    }

    private func swrBar(d: Telemetry?) -> some View {
        let swr = d?.swr ?? 1.0
        let frac = (swr - 1.0) / (SWRScale.max - 1.0)
        let peakFrac = (peakSwr - 1.0) / (SWRScale.max - 1.0)
        let style: BargraphView.FillStyle = {
            if swr >= SWRScale.badThreshold { return .bad }
            if swr >= SWRScale.warnThreshold { return .warn }
            return .normal
        }()
        let valueText = d.map { String(format: "%.2f", $0.swr) } ?? "—"

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("SWR")
                    .font(.subheadline.weight(.semibold))
                Text("1.0 → 5.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            BargraphView(
                fillFraction: frac,
                peakFraction: peakFrac,
                fillStyle: style,
                ticks: ["1.0", "1.2", "1.5", "2.0", "2.5", "3.0", "5.0"]
            )
        }
    }

    private func readouts(d: Telemetry?) -> some View {
        VStack(alignment: .trailing, spacing: 18) {
            powerReadout(d: d)
            swrReadout(d: d)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func powerReadout(d: Telemetry?) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            let pwr = d.map { String(format: "%.1f", $0.powerW) } ?? "—"
            let unit = PowerModeSuffix.suffix(for: d?.mode ?? .average)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(pwr)
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tint)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tint.opacity(0.8))
            }
            let dbw = d.map { String(format: "%.1f", $0.dbw) } ?? "—"
            let dbm = d.map { String(format: "%.1f", $0.dbm) } ?? "—"
            Text("\(dbw) dBW · \(dbm) dBm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func swrReadout(d: Telemetry?) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("SWR")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(d.map { String(format: "%.2f", $0.swr) } ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            let z = d.map { String(format: "%.1f", $0.zOhm) } ?? "—"
            let phase = d.map { String(format: "%.1f", $0.phaseDeg) } ?? "—"
            Text("Z \(z) Ω · ∠ \(phase)°")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
