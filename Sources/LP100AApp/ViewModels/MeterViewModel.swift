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
    @Published var serverURLString: String = ""
    @Published var connectionSheetOpen: Bool = false
    @Published var lastConnectError: String?

    /// True once the user has entered a server URL — drives whether the
    /// connection sheet opens automatically on launch.
    var hasConfiguredServer: Bool {
        guard let url = URL(string: serverURLString),
              url.host?.isEmpty == false else { return false }
        return true
    }

    // View cycle (mirrors VIEWS in the web client)
    @Published var views: [String] = ["normal", "vector"]
    @Published var viewIdx: Int = 0
    @Published var setupOpen: Bool = false

    // Server log level (read from /api/log-level)
    @Published var serverLogLevel: String = "error"

    // Alarm-trip notification edge tracking
    private var lastAlarmTripped: Bool = false
    private var lastAlarmAt: Date = .distantPast

    // Net
    private var ws: WSClient?
    private var configClient: ConfigClient?
    private var listenTask: Task<Void, Never>?

    // UI publish coalescing. The server pushes telemetry at ~10 Hz on a
    // 100 ms poll cadence; a human can't read more than ~5 numbers/sec.
    // Coalesce to 5 Hz so SwiftUI body re-evaluation cost (and the menu-
    // bar label re-render that piggybacks on every objectWillChange) is
    // bounded. Inverse knob: drop `publishInterval` to 0.1 if smoother
    // bargraph motion is wanted.
    static let publishInterval: TimeInterval = 0.2
    private var pendingSnapshot: Telemetry?
    private var lastPublishAt: Date = .distantPast
    private var publishTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.vu3esv.lp100a-app", category: "viewmodel")

    var currentView: String { views[safe: viewIdx] ?? "normal" }

    init() {}

    // MARK: - Connection management

    func start(serverURL: URL) async {
        log.debug("Starting against \(serverURL.absoluteString, privacy: .public)")
        serverURLString = serverURL.absoluteString
        lastConnectError = nil
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
        serverURLString = serverURL.absoluteString
        await stop()
        await start(serverURL: serverURL)
    }

    func disconnect() async {
        await stop()
        connection = .disconnected
        snapshot = nil
    }

    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        publishTask?.cancel()
        publishTask = nil
        pendingSnapshot = nil
        await ws?.stop()
        ws = nil
    }

    enum ConnectionTestResult: Equatable {
        case ok
        case failure(String)
    }

    /// Probe the server's `/healthz` endpoint. Used by the Connect sheet's
    /// "Test connection" button.
    func testConnection(urlString: String) async -> ConnectionTestResult {
        guard let url = URL(string: urlString), url.host?.isEmpty == false else {
            return .failure("Invalid URL")
        }
        let probe = url.appendingPathComponent("/healthz")
        do {
            let (_, resp) = try await URLSession.shared.data(from: probe)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return .ok
            }
            return .failure("Server returned non-2xx")
        } catch {
            return .failure(error.localizedDescription)
        }
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
            // Alarm-edge detection runs on every frame so notifications
            // are timely; the @Published snapshot is coalesced to 5 Hz
            // to bound SwiftUI re-render cost.
            handleAlarmEdge(data: data)
            schedulePublish(data)
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

    /// Coalesces inbound telemetry to a 5 Hz @Published mutation rate.
    /// The latest pending snapshot wins; intermediate frames are dropped
    /// from the UI path (alarm edges still saw them upstream). If the
    /// last publish is older than the throttle window, the new snapshot
    /// is committed immediately; otherwise a single trailing publish is
    /// scheduled to flush the most recent value.
    private func schedulePublish(_ data: Telemetry) {
        pendingSnapshot = data
        if publishTask != nil { return }

        let elapsed = Date().timeIntervalSince(lastPublishAt)
        if elapsed >= Self.publishInterval {
            commitPending()
            return
        }

        let waitNs = UInt64((Self.publishInterval - elapsed) * 1_000_000_000)
        publishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: waitNs)
            await MainActor.run { self?.commitPending() }
        }
    }

    private func commitPending() {
        publishTask = nil
        guard let p = pendingSnapshot else { return }
        pendingSnapshot = nil
        snapshot = p
        lastPublishAt = Date()
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
