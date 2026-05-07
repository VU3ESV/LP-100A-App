import SwiftUI

// Compact label · value pill used in the screen-foot row. Optional click
// behavior matches .pill.clickable in the web client.
struct PillView: View {
    var label: String
    var value: String
    var valueColor: Color = Tokens.accent
    var alarm: Bool = false
    var blinking: Bool = false
    var onTap: (() -> Void)? = nil

    @State private var blinkOn = true

    var body: some View {
        let labelView = Text(label.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(alarm ? Tokens.red : Tokens.swrFg)

        let valueView = Text(value.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.0)
            .foregroundColor(alarm ? Tokens.red : valueColor)
            .opacity(blinking && !blinkOn ? 0.3 : 1.0)
            .onAppear { startBlink() }

        let stack = HStack(spacing: 6) {
            labelView
            Text("·").foregroundColor(Tokens.label)
            valueView
        }

        if let onTap {
            return AnyView(
                stack
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(Tokens.accent.opacity(0.0)))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
            )
        }
        return AnyView(stack)
    }

    private func startBlink() {
        guard blinking else { return }
        Task { @MainActor in
            while true {
                try? await Task.sleep(nanoseconds: 300_000_000)
                blinkOn.toggle()
            }
        }
    }
}
