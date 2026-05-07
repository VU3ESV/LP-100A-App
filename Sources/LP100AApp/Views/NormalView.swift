import SwiftUI

// Normal view: PWR + SWR bargraphs on the left, big numeric readouts on
// the right. Mirrors .view[data-view="normal"] in the web client.
struct NormalView: View {
    var snapshot: Telemetry?
    var peakPwr: Double
    var peakSwr: Double

    var body: some View {
        let d = snapshot
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 14) {
                pwrBar(d: d)
                swrBar(d: d)
            }
            DashedDivider()
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .rotationEffect(.degrees(90))
                .frame(width: 1)
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
        let valueText = d.map { String(format: "%.1f \(suffix)", $0.powerW) } ?? "--"
        let scaleLabel = "\(range.rawValue.lowercased()) · 0–\(Int(max)) W"

        return VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text("PWR")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(Tokens.accent)
                    .frame(width: 36, alignment: .leading)
                Text(scaleLabel.uppercased())
                    .font(.system(size: 11))
                    .tracking(1.0)
                    .foregroundColor(Tokens.label)
                Spacer()
                Text(valueText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Tokens.swrFg)
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
        let valueText = d.map { String(format: "%.2f", $0.swr) } ?? "--"

        return VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text("SWR")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(Tokens.accent)
                    .frame(width: 36, alignment: .leading)
                Text("1.0 → 5.0")
                    .font(.system(size: 11))
                    .tracking(1.0)
                    .foregroundColor(Tokens.label)
                Spacer()
                Text(valueText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Tokens.swrFg)
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
            VStack(alignment: .trailing, spacing: 4) {
                let pwr = d.map { String(format: "%.1f", $0.powerW) } ?? "--"
                let unit = PowerModeSuffix.suffix(for: d?.mode ?? .average)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(pwr)
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundColor(Tokens.power)
                        .shadow(color: Tokens.powerGlow, radius: 8)
                        .tracking(-1)
                    Text(unit == "w" || unit == "W" ? "\(unit)" : unit)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(Tokens.power)
                }
                let dbw = d.map { String(format: "%.1f", $0.dbw) } ?? "--"
                let dbm = d.map { String(format: "%.1f", $0.dbm) } ?? "--"
                Text("\(dbw) dBW · \(dbm) dBm".uppercased())
                    .font(.system(size: 11))
                    .tracking(1.0)
                    .foregroundColor(Tokens.label)
            }
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text("SWR")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(Tokens.label)
                    Text(d.map { String(format: "%.2f", $0.swr) } ?? "--")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundColor(Tokens.swrFg)
                        .shadow(color: Tokens.swrFg.opacity(0.18), radius: 6)
                }
                let z = d.map { String(format: "%.1f", $0.zOhm) } ?? "--"
                let phase = d.map { String(format: "%.1f", $0.phaseDeg) } ?? "--"
                HStack(spacing: 0) {
                    Text("Z ").foregroundColor(Tokens.label)
                    Text(z).foregroundColor(Tokens.swrFg)
                    Text(" Ω · ∠ ").foregroundColor(Tokens.label)
                    Text(phase).foregroundColor(Tokens.swrFg)
                    Text("°").foregroundColor(Tokens.label)
                }
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
