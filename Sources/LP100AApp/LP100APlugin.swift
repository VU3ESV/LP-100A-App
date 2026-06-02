import SwiftUI
import RadioPluginKit

/// Plugin adapter for the Amateur Radio Suite container. Lives inside the
/// `LP100AApp` module so it has internal access to `ContentView` / `MeterViewModel`
/// while keeping the suite's public surface to just this one type.
@MainActor
public final class LP100APlugin: RadioPlugin {
    public static let manifest: RadioPluginManifest? = RadioPluginManifest(
        id: "lp100a",
        name: "LP-100A",
        version: "1.0",
        isolation: .inProcess,                       // first-party, linked into the host
        capabilities: [.networkClient, .notifications],
        systemImage: "gauge",
        author: "VU3ESV"
    )
    public static var metadata: PluginMetadata { manifest!.metadata }

    private let host: PluginHost
    private let vm: MeterViewModel
    private var started = false

    public init(host: PluginHost) {
        self.host = host
        // Point this module's @AppStorage at a per-plugin suite BEFORE building
        // any view, so "serverURL" etc. don't collide with other plugins.
        AppDefaults.store = host.defaults(for: Self.metadata.id)
        self.vm = MeterViewModel()
    }

    public func makeRootView() -> AnyView {
        AnyView(ContentView(vm: vm))
    }

    public func activate() {
        guard !started else { vm.resync(); return }
        started = true
        let store = host.defaults(for: Self.metadata.id)
        if let s = store.string(forKey: "serverURL"),
           let url = URL(string: s), url.host?.isEmpty == false {
            Task { await vm.start(serverURL: url) }
        } else {
            vm.connectionSheetOpen = true
        }
    }

    public var menuCommands: [PluginCommand] {
        [
            PluginCommand(id: "lp100a.resync", title: "Resync LP-100A",
                          shortcut: KeyboardShortcut("r", modifiers: .command)) { [vm] in vm.resync() },
            PluginCommand(id: "lp100a.mode", title: "Cycle Mode",
                          shortcut: KeyboardShortcut("m", modifiers: .command)) { [vm] in vm.sendMode() },
            PluginCommand(id: "lp100a.peak", title: "Toggle Peak / Avg / Tune",
                          shortcut: KeyboardShortcut("p", modifiers: .command)) { [vm] in vm.sendPeak() },
        ]
    }
}
