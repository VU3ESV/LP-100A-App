import SwiftUI
import AppKit
#if canImport(UserNotifications)
import UserNotifications
#endif

@main
struct LP100AApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = MeterViewModel()
    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("menuBarItemEnabled") private var menuBarEnabled: Bool = true

    var body: some Scene {
        WindowGroup {
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
            MenuBarContent(
                vm: vm,
                onShowMain: { showMainWindow() },
                onConnect: { vm.connectionSheetOpen = true },
                onQuit: { NSApp.terminate(nil) }
            )
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

    private func showMainWindow() {
        if let win = NSApp.windows.first(where: { $0.styleMask.contains(.titled) && $0.contentView != nil }) {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate(ignoringOtherApps: true)
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
}
