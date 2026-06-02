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
        if let defaults { AppDefaults.store = defaults }
        return AnyView(ContentView(vm: MeterViewModel()))
    }
}
