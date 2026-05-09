import SwiftUI

// MARK: - Value-typed model

// Everything `NormalView` needs to render, fully resolved into Equatable
// display values. Built once in `ContentView.body` from the snapshot and
// passed in; SwiftUI's `.equatable()` then short-circuits the entire
// `NormalView` subtree (including the bargraph layout pass + info
// strip) when the model is unchanged frame-over-frame.
//
// The raw `Telemetry` is deliberately *not* part of this struct —
// including it would invalidate the model on every wire-level field
// change, even when none of the displayed strings or quantized values
// moved. Instead, every input the view consumes is pre-computed
// (rounded, formatted, quantized) at construction time.
struct NormalModel: Equatable {
    var powerValue: ReadingValue
    var swrValue: ReadingValue
    var swrTint: Color
    var powerBar: BarConfig
    var swrBar: BarConfig
    var dbw: String
    var dbm: String
    var zOhm: String
    var phase: String
}

struct ReadingValue: Equatable {
    var value: String
    var unit: String
}

struct BarConfig: Equatable {
    var fraction: Double
    var scale: Double
    var baseTint: Color
}

extension NormalModel {
    /// Builds a model from a snapshot. Pure function; safe to call on
    /// every `ContentView.body` evaluation.
    static func make(snapshot: Telemetry?) -> NormalModel {
        let range = snapshot?.range ?? .high
        let scale = RangeScale.max(for: range)
        let mode = snapshot?.mode ?? .average

        return NormalModel(
            powerValue: formatPower(snapshot?.powerW, mode: mode),
            swrValue: formatSWR(snapshot?.swr),
            swrTint: swrTintColor(snapshot?.swr ?? 1.0),
            powerBar: bar(for: snapshot?.powerW, scale: scale, baseTint: .cyan),
            swrBar: bar(for: swrFraction(snapshot?.swr ?? 1.0), scale: SWRScale.max, baseTint: .green, isUnitFraction: true),
            dbw: snapshot.map { String(format: "%.1f", $0.dbw) } ?? "—",
            dbm: snapshot.map { String(format: "%.1f", $0.dbm) } ?? "—",
            zOhm: snapshot.map { String(format: "%.1f Ω", $0.zOhm) } ?? "—",
            phase: snapshot.map { String(format: "%.1f°", $0.phaseDeg) } ?? "—"
        )
    }
}

// MARK: - Pure helpers

private func formatPower(_ w: Double?, mode: PeakMode) -> ReadingValue {
    guard let w, !w.isNaN else { return .init(value: "—", unit: "W") }
    let suffix = PowerModeSuffix.suffix(for: mode)
    if w >= 1000 { return .init(value: String(format: "%.2f", w / 1000.0), unit: "k\(suffix)") }
    if w >= 100  { return .init(value: String(format: "%.0f", w), unit: suffix) }
    return .init(value: String(format: "%.1f", w), unit: suffix)
}

private func formatSWR(_ s: Double?) -> ReadingValue {
    guard let s, !s.isNaN else { return .init(value: "—", unit: "") }
    return .init(value: String(format: "%.2f", s), unit: "")
}

private func swrTintColor(_ swr: Double) -> Color {
    if swr >= SWRScale.badThreshold { return .red }
    if swr >= SWRScale.warnThreshold { return .yellow }
    return .accentColor
}

private func swrFraction(_ swr: Double) -> Double {
    (swr - 1.0) / (SWRScale.max - 1.0)
}

// Quantize the bar fraction to 1 % steps. The eye can't resolve finer
// movement on a 6-pt bar, and step-quantising is what lets the
// surrounding `Equatable` model skip body re-eval when adjacent
// samples land in the same step.
private func bar(for value: Double?, scale: Double, baseTint: Color, isUnitFraction: Bool = false) -> BarConfig {
    let v = value ?? 0
    let raw = isUnitFraction ? v : (scale > 0 ? v / scale : 0)
    let quantized = (raw * 100).rounded() / 100
    return BarConfig(fraction: quantized, scale: scale, baseTint: baseTint)
}

// MARK: - View

// Power & SWR readout panel modeled after LP-700-App's PowerSWRView.
// Two reading cards on top (Power + SWR), then an inline info strip
// with dBW · dBm · |Z| · Phase.
//
// View is `Equatable` over its `model`; SwiftUI's `.equatable()` lets
// the entire subtree skip body + layout when display values are
// unchanged frame-over-frame — extremely common after `formatPower`
// rounds and the bar fraction quantizes into the same 1 % step.
struct NormalView: View, Equatable {
    let model: NormalModel

    static func == (lhs: NormalView, rhs: NormalView) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ReadingCard(label: "Power",
                            value: model.powerValue,
                            tint: .accentColor,
                            bar: model.powerBar)
                    .equatable()
                ReadingCard(label: "SWR",
                            value: model.swrValue,
                            tint: model.swrTint,
                            bar: model.swrBar)
                    .equatable()
            }

            // Plain HStack inside the parent Panel — no separate
            // CompactPanel wrapper, so we don't end up with a rounded
            // card nested inside another rounded card.
            Divider()
            HStack(spacing: 8) {
                statusItem(label: "dBW", value: model.dbw)
                Spacer(minLength: 4)
                statusItem(label: "dBm", value: model.dbm)
                Spacer(minLength: 4)
                statusItem(label: "|Z|", value: model.zOhm)
                Spacer(minLength: 4)
                statusItem(label: "Phase", value: model.phase)
            }
            .frame(maxWidth: .infinity)
        }
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

// MARK: - Pieces

struct ReadingCard: View, Equatable {
    var label: String
    var value: ReadingValue
    var tint: Color
    var bar: BarConfig? = nil

    static func == (lhs: ReadingCard, rhs: ReadingCard) -> Bool {
        lhs.label == rhs.label
            && lhs.value == rhs.value
            && lhs.tint == rhs.tint
            && lhs.bar == rhs.bar
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

private struct PowerBar: View, Equatable {
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
        // No `.animation(value: fraction)` — implicit animations run a
        // 60 Hz CoreAnimation transaction until they settle, and at the
        // 5 Hz mutation rate we never settle. The fraction is already
        // quantized at construction time, so changes step-jump cleanly.
    }
}
