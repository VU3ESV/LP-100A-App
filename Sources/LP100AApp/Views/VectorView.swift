import SwiftUI

// Vector impedance view: |Z|, phase, R, X cells + polar compass.
// Mirrors .view[data-view="vector"] in the web client.
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
        HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 14) {
                HStack(spacing: 22) {
                    cell(label: "|Z|", value: format(z, 1), unit: "Ω")
                    cell(label: "Phase", value: format(phase, 1), unit: "°")
                }
                HStack(spacing: 22) {
                    cell(label: "R (resistive)", value: format(r, 1), unit: "Ω")
                    cell(label: "X (reactive)",
                         value: (x >= 0 ? "+" : "") + format(x, 1),
                         unit: "Ω")
                }
                fullCell(label: "SWR · |Γ| reflection",
                         value: "\(format(swr, 2)) · |Γ| \(format(gamma, 3))")
            }
            CompassView(z: z, phaseDeg: phase)
                .frame(width: 220, height: 220)
        }
    }

    private func cell(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(Tokens.label)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(Tokens.accent)
                Text(unit)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Tokens.label)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
    }

    private func fullCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(Tokens.label)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(Tokens.swrFg)
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
    }

    private func format(_ v: Double, _ digits: Int) -> String {
        guard !v.isNaN else { return "--" }
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

            // Background
            let bg = Path(ellipseIn: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
            ctx.fill(bg, with: .radialGradient(
                Gradient(colors: [Color(hex: 0x0a0e12), Color(hex: 0x06080a)]),
                center: center, startRadius: 0, endRadius: outerR))
            ctx.stroke(bg, with: .color(Tokens.dashed), lineWidth: 1)

            // Cross axes
            var axes = Path()
            axes.move(to: CGPoint(x: outerR * 0.16, y: center.y))
            axes.addLine(to: CGPoint(x: size.width - outerR * 0.16, y: center.y))
            axes.move(to: CGPoint(x: center.x, y: outerR * 0.16))
            axes.addLine(to: CGPoint(x: center.x, y: size.height - outerR * 0.16))
            ctx.stroke(axes, with: .color(Tokens.grid), lineWidth: 1)

            // Inner ring (dashed)
            let ring = Path(ellipseIn: CGRect(
                x: center.x - ringR, y: center.y - ringR,
                width: ringR * 2, height: ringR * 2))
            ctx.stroke(ring, with: .color(Tokens.dashed),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Vector tip
            let phRad = phaseDeg * .pi / 180.0
            let norm = min(1.0, z / 100.0)
            let tipX = norm * cos(phRad) * Double(ringR)
            let tipY = -norm * sin(phRad) * Double(ringR)
            let tip = CGPoint(x: center.x + tipX, y: center.y + tipY)

            // Needle
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: tip)
            ctx.stroke(needle, with: .linearGradient(
                Gradient(colors: [Color.clear, Tokens.accent]),
                startPoint: center, endPoint: tip), lineWidth: 2)

            // Tip dot
            let dotR: CGFloat = 4
            let dotPath = Path(ellipseIn: CGRect(
                x: tip.x - dotR, y: tip.y - dotR,
                width: dotR * 2, height: dotR * 2))
            ctx.fill(dotPath, with: .color(Tokens.peak))
        }
        .overlay(alignment: .trailing) { axisLabel("+R").padding(.trailing, 4) }
        .overlay(alignment: .leading) { axisLabel("−R").padding(.leading, 4) }
        .overlay(alignment: .top) { axisLabel("+jX").padding(.top, 4) }
        .overlay(alignment: .bottom) { axisLabel("−jX").padding(.bottom, 4) }
    }

    private func axisLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .foregroundColor(Tokens.label)
    }
}
