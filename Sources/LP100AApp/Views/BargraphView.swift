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

                    // Realtime meter: avoid interpolation. A linear fill
                    // animation with a 90 ms duration shows up as visible
                    // lag between the snapshot and the rendered bar.
                    Rectangle()
                        .fill(fillGradient)
                        .frame(width: max(0, min(1, fillFraction)) * geo.size.width, height: 18)

                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 22)
                        .offset(x: max(0, min(1, peakFraction)) * geo.size.width - 1, y: -2)
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
}
