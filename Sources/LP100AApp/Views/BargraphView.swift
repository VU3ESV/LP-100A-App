import SwiftUI

// Horizontal segmented bargraph with sticky-peak marker. Mirrors the
// .track / .fill / .peak DOM in the web client.
struct BargraphView: View {
    enum FillStyle {
        case normal
        case warn
        case bad
    }

    var fillFraction: Double      // 0–1
    var peakFraction: Double      // 0–1
    var fillStyle: FillStyle = .normal
    var ticks: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track: tick-grid background.
                    track
                        .frame(height: 22)

                    // Fill.
                    Rectangle()
                        .fill(fillGradient)
                        .frame(width: max(0, min(1, fillFraction)) * geo.size.width, height: 22)
                        .shadow(color: glowColor, radius: 8)
                        .animation(.linear(duration: 0.09), value: fillFraction)

                    // Peak marker.
                    Rectangle()
                        .fill(Tokens.peak)
                        .frame(width: 2, height: 26)
                        .shadow(color: Tokens.peak, radius: 4)
                        .offset(x: max(0, min(1, peakFraction)) * geo.size.width - 1, y: -2)
                        .animation(.easeOut(duration: 0.2), value: peakFraction)
                        .opacity(0.9)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.black, lineWidth: 1)
                )
            }
            .frame(height: 22)

            HStack {
                ForEach(Array(ticks.enumerated()), id: \.offset) { idx, t in
                    Text(t)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Tokens.tick)
                        .tracking(0.5)
                    if idx < ticks.count - 1 { Spacer() }
                }
            }
        }
    }

    private var track: some View {
        ZStack {
            Tokens.grid
            // Tick-stripe overlay (every 8px, 1px-wide black gap).
            GeometryReader { geo in
                Canvas { ctx, size in
                    var x: CGFloat = 8
                    while x < size.width {
                        let stripe = Path(CGRect(x: x, y: 0, width: 1, height: size.height))
                        ctx.fill(stripe, with: .color(Color.black.opacity(0.7)))
                        x += 9
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private var fillGradient: LinearGradient {
        switch fillStyle {
        case .normal:
            return LinearGradient(colors: [Tokens.barTop, Tokens.bar, Tokens.barBottom],
                                  startPoint: .top, endPoint: .bottom)
        case .warn:
            return LinearGradient(colors: [Tokens.warnTop, Tokens.warnMid, Tokens.warnBottom],
                                  startPoint: .top, endPoint: .bottom)
        case .bad:
            return LinearGradient(colors: [Tokens.badTop, Tokens.badMid, Tokens.badBottom],
                                  startPoint: .top, endPoint: .bottom)
        }
    }

    private var glowColor: Color {
        switch fillStyle {
        case .normal: return Tokens.barGlow
        case .warn:   return Tokens.yellow.opacity(0.45)
        case .bad:    return Tokens.red.opacity(0.55)
        }
    }
}
