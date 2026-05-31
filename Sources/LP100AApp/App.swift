import SwiftUI
import AppKit
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Standalone-app entry. In the suite this type is unused (the container owns
/// the process); the plugin path is `LP100APlugin`. Kept `public` so the thin
/// `LP100AAppMain` executable target can call `.main()` on it.
public struct LP100AStandaloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = MeterViewModel()

    public init() {}

    @AppStorage("serverURL", store: AppDefaults.store) private var serverURL: String = ""
    @AppStorage("menuBarItemEnabled", store: AppDefaults.store) private var menuBarEnabled: Bool = true

    public var body: some Scene {
        // `Window` (not `WindowGroup`) is a singleton scene: closing the
        // red-dot button hides it instead of disposing the SwiftUI scene,
        // and `openWindow(id: "main")` from the menu-bar restores it.
        // With `WindowGroup`, the window is fully torn down on close, so
        // there is nothing for "Show LP-100A Window" to bring forward.
        Window("LP-100A", id: "main") {
            ContentView(vm: vm)
                .background(OpenPrefsCapture())
                .task { await bootstrap() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if vm.connection == .connected { vm.resync() }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    Task {
                        if let u = URL(string: serverURL), u.host?.isEmpty == false {
                            await vm.reconnect(serverURL: u)
                        }
                    }
                }
        }
        .commands { menuCommands }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 440)

        Settings {
            PreferencesView(vm: vm)
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent(vm: vm, onQuit: { NSApp.terminate(nil) })
        } label: {
            MenuBarLabel(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }

    private func bootstrap() async {
        requestNotificationPermission()
        if let url = URL(string: serverURL), url.host?.isEmpty == false {
            await vm.start(serverURL: url)
        } else {
            // First launch — open the Connect sheet automatically.
            vm.connectionSheetOpen = true
        }
        // Screenshot/debug launch flags. `open -a LP-100A-App --args
        // --open-setup` flips the SETUP overlay on right after bootstrap
        // so the docs script can capture it without UI scripting /
        // accessibility permission. `--view=vector` switches to that
        // view. `--open-prefs` is wired through OpenPrefsCapture below.
        if CommandLine.arguments.contains("--open-setup") {
            vm.setupOpen = true
        }
        if let viewArg = CommandLine.arguments.first(where: { $0.hasPrefix("--view=") }) {
            let viewName = String(viewArg.dropFirst("--view=".count))
            if let idx = vm.views.firstIndex(of: viewName) {
                vm.setView(idx)
            }
        }
    }

    private func requestNotificationPermission() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        #endif
    }

    @CommandsBuilder
    private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .appSettings) {
            Button("Connect to Server…") { vm.connectionSheetOpen = true }
                .keyboardShortcut("k", modifiers: [.command])
            Button(vm.connection == .connected ? "Disconnect" : "Reconnect") {
                if vm.connection == .connected {
                    Task { await vm.disconnect() }
                } else if let url = URL(string: serverURL), url.host?.isEmpty == false {
                    Task { await vm.reconnect(serverURL: url) }
                } else {
                    vm.connectionSheetOpen = true
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Normal") { vm.setView(0) }
                .keyboardShortcut("1", modifiers: [.command])
            Button("Vector Z") { vm.setView(1) }
                .keyboardShortcut("2", modifiers: [.command])
            Divider()
            Button(vm.setupOpen ? "Close Setup" : "Open Setup") { vm.toggleSetup() }
                .keyboardShortcut(".", modifiers: [.command])
            Button("Resync") { vm.resync() }
                .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu("Meter") {
            Button("Cycle Mode") { vm.sendMode() }
                .keyboardShortcut("m", modifiers: [.command])
            Button("Step Alarm Setpoint") { vm.sendAlarm() }
                .keyboardShortcut("a", modifiers: [.command])
            Button("Toggle Peak / Avg / Tune") { vm.sendPeak() }
                .keyboardShortcut("p", modifiers: [.command])
        }
    }

}

// Invisible helper that pops the Settings window when `--open-prefs` is on
// argv, so the screenshot driver can capture Preferences without needing
// Accessibility permission for `osascript` keystroke. Tries the macOS 14+
// selector first, falls back to the macOS 13 one. On macOS 26+ where Apple
// removed both selectors, capture Preferences manually with ⌘,.
private struct OpenPrefsCapture: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard CommandLine.arguments.contains("--open-prefs") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NSApp.activate(ignoringOtherApps: true)
                    if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let menuBar = UserDefaults.standard.object(forKey: "menuBarItemEnabled") as? Bool ?? true
        return !menuBar
    }

    // Dock-icon click after the main window was closed. With the singleton
    // `Window` scene, AppKit re-orders the hidden window front when this
    // returns true; without overriding, the bounce is a no-op.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }
}
