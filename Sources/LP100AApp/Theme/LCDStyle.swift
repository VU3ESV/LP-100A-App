import SwiftUI

// Native-styled panels replacing the prior LCD case/bezel. The instrument
// readouts live inside a single GroupBox-equivalent rounded surface using
// the system's regular material so it sits comfortably in any window
// background (light/dark/vibrant).
struct Panel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            )
    }
}

// Section header used inside panels — small caps, secondary color, with
// an optional trailing accessory (e.g. callsign).
struct PanelHeader: View {
    var title: String
    var trailing: AnyView? = nil

    init(title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
    }
}
