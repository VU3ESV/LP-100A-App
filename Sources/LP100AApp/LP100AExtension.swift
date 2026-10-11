import SwiftUI

/// Public entry point for hosting LP-100A **out-of-process** as an ExtensionKit `.appex`.
///
/// The extension target is a separate module, so it can't see LP-100A's `internal` views.
/// This factory hands it the same UI the in-process `LP100APlugin` shows, keeping every
/// other LP-100A type private. See `Xcode/Extension/LP100APluginExtension.swift`.
public enum LP100AExtension {
    /// Build the LP-100A root view for an out-of-process host. `defaults` backs the app's
    /// `@AppStorage` (the extension's own sandboxed `UserDefaults`); pass an app-group
    /// suite if the container and extension should share connection settings.
    @MainActor
    public static func rootView(defaults: UserDefaults? = nil) -> AnyView {
        // Must happen before `HostedRootView` is built: its `@AppStorage` captures the store.
        if let defaults { AppDefaults.store = defaults }
        return AnyView(HostedRootView())
    }
}

/// Root of the hosted (.appex) UI. Owns the view model for the life of the hosted scene
/// and bootstraps the connection the same way the other two entry points do —
/// `LP100AStandaloneApp.bootstrap()` for the standalone window and
/// `LP100APlugin.activate()` for the in-process plugin:
///
/// - a saved server URL → connect to it as soon as the view appears;
/// - nothing saved yet → open the Connect sheet once. `ConnectionSheet` persists the URL
///   on Connect, so every later launch in the Suite connects on its own.
///
/// Before this view existed the hosted plugin built `ContentView` around a fresh
/// `MeterViewModel` and never called `start(serverURL:)`, so it sat disconnected until the
/// operator opened the connection settings on every launch.
struct HostedRootView: View {
    @StateObject private var vm = MeterViewModel()
    @AppStorage("serverURL", store: AppDefaults.store) private var serverURL: String = ""

    var body: some View {
        // `embedded: true` renders the toolbar controls inline. A hosted .appex has no window
        // title bar, so SwiftUI `.toolbar` items never appear; the standalone app (embedded:
        // false) keeps its window toolbar.
        ContentView(vm: vm, embedded: true, hosted: true)
            .task { await bootstrap() }
    }

    private func bootstrap() async {
        if let url = MeterViewModel.configuredServerURL(serverURL) {
            await vm.start(serverURL: url)
        } else {
            vm.connectionSheetOpen = true
        }
    }
}
