import SwiftUI
import ExtensionFoundation
import ExtensionKit
import LP100AApp

/// LP-100A as a sandboxed, crash-isolated ExtensionKit `.appex` for the Amateur Radio Suite.
/// It declares the suite's extension point (see Info.plist) and vends LP-100A's real UI via
/// `LP100AExtension.rootView()`; the suite embeds it with `EXHostViewController`.
///
/// SwiftPM cannot build `.appex` bundles — this target is built by the Xcode project
/// (`Xcode/project.yml`). The standalone `LP-100A-App` and the in-process `LP100APlugin`
/// are unchanged.
@main
struct LP100APluginExtension: AppExtension {
    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(
            PrimitiveAppExtensionScene(id: "primary") {
                LP100AExtension.rootView()
            }
        )
    }
}
