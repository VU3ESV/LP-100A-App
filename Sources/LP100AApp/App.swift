import SwiftUI
import AppKit
#if canImport(UserNotifications)
import UserNotifications
#endif

@main
struct LP100AApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = MeterViewModel()
    @AppStorage("serverURL") private var serverURL: String = "http://localhost:8088"
    @AppStorage("menuBarItemEnabled") private var menuBarEnabled: Bool = true

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .task { await bootstrap() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    vm.resync()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    Task {
                        if let u = URL(string: serverURL) { await vm.reconnect(serverURL: u) }
                    }
                }
        }
        .commands { menuCommands }
        .windowResizability(.contentMinSize)

        Settings {
            PreferencesView(onChange: { url in
                Task { await vm.reconnect(serverURL: url) }
            })
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent(
                vm: vm,
                onShowMain: { showMainWindow() },
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            MenuBarLabel(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }

    private func bootstrap() async {
        requestNotificationPermission()
        if let url = URL(string: serverURL) {
            await vm.start(serverURL: url)
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
            Button("Mode") { vm.sendMode() }
                .keyboardShortcut("m", modifiers: [.command])
            Button("Alarm Step") { vm.sendAlarm() }
                .keyboardShortcut("a", modifiers: [.command])
            Button("Peak / Avg / Tune") { vm.sendPeak() }
                .keyboardShortcut("p", modifiers: [.command])
        }
    }

    private func showMainWindow() {
        if let win = NSApp.windows.first(where: { $0.contentView != nil && $0.title.isEmpty == false || $0.styleMask.contains(.titled) }) {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app alive while menu-bar item is enabled.
        let menuBar = UserDefaults.standard.object(forKey: "menuBarItemEnabled") as? Bool ?? true
        return !menuBar
    }
}
