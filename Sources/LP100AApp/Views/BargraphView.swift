import SwiftUI

// Horizontal segmented bargraph with sticky-peak marker. Track uses a
// system-secondary background; fill colors are functional (teal / yellow /
// red) so signal severity reads at a glance.
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
                    track
                        .frame(height: 18)

                    Rectangle()
                        .fill(fillGradient)
                        .frame(width: max(0, min(1, fillFraction)) * geo.size.width, height: 18)
                        .shadow(color: glowColor, radius: 6)
                        .animation(.linear(duration: 0.09), value: fillFraction)

                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 22)
                        .shadow(color: .white.opacity(0.7), radius: 3)
                        .offset(x: max(0, min(1, peakFraction)) * geo.size.width - 1, y: -2)
                        .animation(.easeOut(duration: 0.2), value: peakFraction)
                        .opacity(0.85)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .frame(height: 18)

            HStack {
                ForEach(Array(ticks.enumerated()), id: \.offset) { idx, t in
                    Text(t)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if idx < ticks.count - 1 { Spacer() }
                }
            }
        }
    }

    private var track: some View {
        Rectangle().fill(Color.secondary.opacity(0.12))
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
        case .warn:   return Color.yellow.opacity(0.45)
        case .bad:    return Color.red.opacity(0.55)
        }
    }
}
