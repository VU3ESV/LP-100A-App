import SwiftUI

// Native-styled panel surface for instrument readouts. Mirrors the
// LP-700-App `Panel` so the two clients feel like siblings.
struct Panel<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// Compact variant used for the bottom status / keypad row.
struct CompactPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// Small-caps section header — 11pt semibold uppercase with extra letter
// spacing, secondary tint. Matches LP-700-App's `PanelHeader`.
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
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.12 * 11)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if let trailing { trailing }
        }
    }
}
