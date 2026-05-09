import SwiftUI

// Vector impedance view: |Z|, phase, R, X cells + polar compass.
struct VectorView: View {
    var snapshot: Telemetry?

    private var z: Double { snapshot?.zOhm ?? 0 }
    private var phase: Double { snapshot?.phaseDeg ?? 0 }
    private var phaseRad: Double { phase * .pi / 180.0 }
    private var r: Double { z * cos(phaseRad) }
    private var x: Double { z * sin(phaseRad) }
    private var swr: Double { snapshot?.swr ?? 1 }
    private var gamma: Double { swr > 1 ? (swr - 1) / (swr + 1) : 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    cell(label: "|Z|", value: format(z, 1), unit: "Ω")
                    cell(label: "Phase", value: format(phase, 1), unit: "°")
                }
                HStack(spacing: 8) {
                    cell(label: "R (resistive)", value: format(r, 1), unit: "Ω")
                    cell(label: "X (reactive)",
                         value: (x >= 0 ? "+" : "") + format(x, 1),
                         unit: "Ω")
                }
                fullCell(label: "SWR · |Γ| reflection",
                         value: "\(format(swr, 2))  ·  |Γ| \(format(gamma, 3))")
            }
            CompassView(z: z, phaseDeg: phase)
                .frame(width: 180, height: 180)
        }
    }

    private func cell(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.12 * 11)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tint)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func fullCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.12 * 11)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func format(_ v: Double, _ digits: Int) -> String {
        guard !v.isNaN else { return "—" }
        return String(format: "%.\(digits)f", v)
    }
}

private struct CompassView: View {
    var z: Double
    var phaseDeg: Double

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR = min(size.width, size.height) / 2
            let ringR = outerR * 0.64

            let bg = Path(ellipseIn: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
            ctx.fill(bg, with: .color(Color.secondary.opacity(0.05)))
            ctx.stroke(bg, with: .color(Color.secondary.opacity(0.4)), lineWidth: 1)

            var axes = Path()
            axes.move(to: CGPoint(x: outerR * 0.16, y: center.y))
            axes.addLine(to: CGPoint(x: size.width - outerR * 0.16, y: center.y))
            axes.move(to: CGPoint(x: center.x, y: outerR * 0.16))
            axes.addLine(to: CGPoint(x: center.x, y: size.height - outerR * 0.16))
            ctx.stroke(axes, with: .color(Color.secondary.opacity(0.3)), lineWidth: 1)

            let ring = Path(ellipseIn: CGRect(
                x: center.x - ringR, y: center.y - ringR,
                width: ringR * 2, height: ringR * 2))
            ctx.stroke(ring, with: .color(Color.secondary.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            let phRad = phaseDeg * .pi / 180.0
            let norm = min(1.0, z / 100.0)
            let tipX = norm * cos(phRad) * Double(ringR)
            let tipY = -norm * sin(phRad) * Double(ringR)
            let tip = CGPoint(x: center.x + tipX, y: center.y + tipY)

            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: tip)
            ctx.stroke(needle, with: .color(.accentColor), lineWidth: 2)

            let dotR: CGFloat = 4
            let dotPath = Path(ellipseIn: CGRect(
                x: tip.x - dotR, y: tip.y - dotR,
                width: dotR * 2, height: dotR * 2))
            ctx.fill(dotPath, with: .color(.accentColor))
        }
        .overlay(alignment: .trailing) { axisLabel("+R").padding(.trailing, 4) }
        .overlay(alignment: .leading) { axisLabel("−R").padding(.leading, 4) }
        .overlay(alignment: .top) { axisLabel("+jX").padding(.top, 4) }
        .overlay(alignment: .bottom) { axisLabel("−jX").padding(.bottom, 4) }
    }

    private func axisLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}
