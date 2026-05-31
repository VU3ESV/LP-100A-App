import Foundation

/// Backing store for this app's `@AppStorage` keys.
///
/// Standalone: `store` stays `nil`, so `@AppStorage` uses `UserDefaults.standard`
/// (the app's own bundle domain) — unchanged behavior.
///
/// In the suite: `LP100APlugin` sets `store` to a per-plugin suite at construction,
/// before any view is built, so keys like "serverURL" don't collide with the other
/// plugins sharing the container's process.
enum AppDefaults {
    static var store: UserDefaults?
    /// Non-optional accessor for code that reads defaults directly.
    static var resolved: UserDefaults { store ?? .standard }
}
