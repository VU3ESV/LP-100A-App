import SwiftUI

// Top "LP-100A · WebSocket Bridge" + connection-state pill, mirroring the
// .topbar in the web client.
struct StatusBar: View {
    var state: WSClient.ConnectionState
    var statusText: String { Self.label(for: state) }

    var body: some View {
        HStack {
            Text("LP-100A · WebSocket Bridge")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Tokens.swrFg)
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.8), radius: state == .connected ? 4 : 0)
                Text(statusText.uppercased())
                    .font(.system(size: 11))
                    .tracking(0.8)
                    .foregroundColor(Tokens.muted)
            }
        }
    }

    private var dotColor: Color {
        switch state {
        case .connected: return Tokens.green
        case .reconnecting: return Tokens.yellow
        case .disconnected: return Tokens.red
        }
    }

    static func label(for s: WSClient.ConnectionState) -> String {
        switch s {
        case .connected: return "connected"
        case .reconnecting: return "reconnecting…"
        case .disconnected: return "disconnected"
        }
    }
}
