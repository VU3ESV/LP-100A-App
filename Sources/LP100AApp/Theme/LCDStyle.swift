import SwiftUI

// LCD bezel surface — dark inset rectangle with faint scan-lines. Mirrors
// the .lcd class plus its ::before scan-line overlay in the web client.
struct LCDSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.lcd)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Tokens.lcdBorder, lineWidth: 1)
                )
                .shadow(color: Tokens.bar.opacity(0.06), radius: 30)

            ScanLines()
                .opacity(0.5)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            content()
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
        }
    }
}

private struct ScanLines: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let stripe = Path(CGRect(x: 0, y: 0, width: size.width, height: 1))
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(stripe.applying(.init(translationX: 0, y: y)),
                             with: .color(.white.opacity(0.012)))
                    y += 3
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

// Outer case — gradient + drop shadow.
struct MeterCase<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Tokens.caseBg, Color(hex: 0x0a0d11)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Tokens.bezelEdge, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
            )
    }
}

// Section divider that draws a dashed line below content. Replaces the
// ::after / border-top: 1px dashed treatments in the web client.
struct DashedDivider: View {
    var color: Color = Tokens.dashed
    var body: some View {
        Line()
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// Uppercased small caption used throughout (label / title rows).
struct Caption: View {
    var text: String
    var color: Color = Tokens.label
    var tracking: CGFloat = 1.4
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(tracking)
            .foregroundColor(color)
    }
}
