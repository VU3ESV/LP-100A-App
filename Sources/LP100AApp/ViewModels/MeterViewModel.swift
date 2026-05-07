import Foundation
import SwiftUI
import os.log
#if canImport(UserNotifications)
import UserNotifications
#endif

// Single source of truth for the UI. Owns connection lifecycle, the latest
// telemetry snapshot, the view-cycle, and SETUP overlay state.
@MainActor
final class MeterViewModel: ObservableObject {
    // Telemetry / connection
    @Published var snapshot: Telemetry?
    @Published var connection: WSClient.ConnectionState = .disconnected
    @Published var statusBanner: String?
    @Published var allowControl: Bool = true

    // View cycle (mirrors VIEWS in the web client)
    @Published var views: [String] = ["normal", "vector"]
    @Published var viewIdx: Int = 0
    @Published var setupOpen: Bool = false

    // Sticky peaks
    @Published var peakPwr: Double = 0
    @Published var peakSwr: Double = 1.0
    private var peakPwrAt: Date = .distantPast
    private var peakSwrAt: Date = .distantPast

    // Server log level (read from /api/log-level)
    @Published var serverLogLevel: String = "error"

    // Alarm-trip notification edge tracking
    private var lastAlarmTripped: Bool = false
    private var lastAlarmAt: Date = .distantPast

    // Net
    private var ws: WSClient?
    private var configClient: ConfigClient?
    private var listenTask: Task<Void, Never>?
    private var decayTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.vu3esv.lp100a-app", category: "viewmodel")

    var currentView: String { views[safe: viewIdx] ?? "normal" }

    init() {
        startDecayLoop()
    }

    // MARK: - Connection management

    func start(serverURL: URL) async {
        log.debug("Starting against \(serverURL.absoluteString, privacy: .public)")
        let cfg = ConfigClient(baseURL: serverURL)
        configClient = cfg

        // Bootstrap from /api/config (best-effort)
        if let server = try? await cfg.fetchConfig() {
            let supported = server.views.filter { ["normal", "vector"].contains($0) }
            views = supported.isEmpty ? ["normal", "vector"] : supported
            allowControl = server.allowControl
        }
        if let lvl = try? await cfg.fetchLogLevel() { serverLogLevel = lvl.level }

        let ws = WSClient(baseURL: serverURL)
        self.ws = ws
        await ws.start()
        listenTask?.cancel()
        let events = ws.events
        listenTask = Task { [weak self] in
            guard let self else { return }
            for await event in events {
                await self.handle(event: event)
            }
        }
    }

    func reconnect(serverURL: URL) async {
        await stop()
        await start(serverURL: serverURL)
    }

    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        await ws?.stop()
        ws = nil
    }

    // MARK: - Commands

    func sendMode() {
        sendCommand(.modeStep)
        viewIdx = (viewIdx + 1) % max(views.count, 1)
    }

    func sendAlarm() { sendCommand(.alarmStep) }
    func sendPeak() { sendCommand(.peakToggle) }
    func resync() { sendRaw(.resync) }

    private func sendCommand(_ action: CommandAction) {
        guard allowControl, connection == .connected else { return }
        sendRaw(.command(id: UUID().uuidString, action: action))
    }

    private func sendRaw(_ frame: ClientFrame) {
        Task { [ws] in
            try? await ws?.send(frame)
        }
    }

    // MARK: - Setup / log level

    func toggleSetup() { setupOpen.toggle() }

    func setView(_ idx: Int) {
        guard idx >= 0, idx < views.count else { return }
        viewIdx = idx
    }

    func setLogLevel(_ level: String) async {
        guard let configClient else { return }
        if let updated = try? await configClient.setLogLevel(level) {
            serverLogLevel = updated.level
        }
    }

    // MARK: - Event handling

    private func handle(event: WSClient.Event) async {
        switch event {
        case .stateChanged(let s):
            connection = s
        case .frame(let frame):
            applyFrame(frame)
        case .parseError(let msg):
            log.warning("WS parse error: \(msg, privacy: .public)")
        }
    }

    private func applyFrame(_ frame: ServerFrame) {
        switch frame {
        case .telemetry(_, _, let data):
            snapshot = data
            updatePeaks(from: data)
            handleAlarmEdge(data: data)
        case .heartbeat:
            break
        case .status(let level, let msg):
            statusBanner = "[\(level.uppercased())] \(msg)"
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { self?.statusBanner = nil }
            }
        case .ack(_, let ok, let err):
            if !ok, let err {
                statusBanner = "Server rejected: \(err)"
            }
        case .unknown:
            break
        }
    }

    private func updatePeaks(from d: Telemetry) {
        let now = Date()
        if d.powerW > peakPwr { peakPwr = d.powerW; peakPwrAt = now }
        if d.swr > peakSwr { peakSwr = d.swr; peakSwrAt = now }
    }

    private func startDecayLoop() {
        decayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000) // ~16 fps
                await MainActor.run {
                    guard let self else { return }
                    let now = Date()
                    if now.timeIntervalSince(self.peakPwrAt) > 1.5 {
                        self.peakPwr = max(0, self.peakPwr - self.peakPwr * 0.05)
                    }
                    if now.timeIntervalSince(self.peakSwrAt) > 1.5 {
                        self.peakSwr = max(1.0, self.peakSwr - (self.peakSwr - 1.0) * 0.05)
                    }
                }
            }
        }
    }

    private func handleAlarmEdge(data: Telemetry) {
        defer { lastAlarmTripped = data.alarmTripped }
        guard data.alarmTripped, !lastAlarmTripped else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAlarmAt) > 30 else { return }
        lastAlarmAt = now
        postAlarmNotification(swr: data.swr, setpoint: data.alarmSetpoint.rawValue)
    }

    private func postAlarmNotification(swr: Double, setpoint: String) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "LP-100A — SWR alarm"
        content.body = String(format: "SWR %.2f above %@ setpoint", swr, setpoint)
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
        #endif
    }
}

extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
