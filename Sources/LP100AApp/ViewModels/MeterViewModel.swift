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
    // Coalesce to 2 Hz — every layout pass walks the toolbar +
    // meter-face + keypad + menu-bar-label tree, which is tens of ms of
    // work at idle. Combined with the publish-time signature dedup
    // below, this caps the SwiftUI layout cost at ~2 invalidations/sec
    // when values genuinely change, and ~0 invalidations/sec when the
    // meter is at noise-floor wobble. Inverse knob: drop to 0.2 (5 Hz)
    // if smoother bargraph motion is wanted during sustained TX.
    static let publishInterval: TimeInterval = 0.5
    private var pendingSnapshot: Telemetry?
    private var lastPublishAt: Date = .distantPast
    private var publishTask: Task<Void, Never>?

    /// Display-level signature of the last published snapshot. Computed
    /// once at commit time; comparing the new candidate against this is
    /// dramatically cheaper than letting SwiftUI re-evaluate the whole
    /// view subtree and discover via `Equatable` at the leaves that
    /// nothing visible moved. This is the dominant CPU win on noise-
    /// floor wobble (Z/phase jiggle ~0.1 between polls but round to the
    /// same `%.1f` strings).
    private var lastPublishedSignature: PublishSignature?

    private struct PublishSignature: Equatable {
        let powerStr: String
        let powerSuffix: String
        let swrStr: String
        let dbwStr: String
        let dbmStr: String
        let zStr: String
        let phaseStr: String
        let range: PowerRange
        let mode: PeakMode
        let alarmSetpoint: AlarmSetpoint
        let alarmTripped: Bool
        let callsign: String
        let powerBarBucket: Int   // 0…100, quantized to 1 % steps
        let swrBarBucket: Int     // ditto, on the 1.0 → 5.0 scale

        init(_ d: Telemetry) {
            // Mirror the formatting in NormalView.NormalModel.make so
            // the signature is exactly the set of strings the view will
            // produce. Power suffix follows the LP-100A LCD convention
            // (lower-case `w` for Average must not be uppercased).
            let suffix = PowerModeSuffix.suffix(for: d.mode)
            if d.powerW >= 1000 {
                powerStr = String(format: "%.2f", d.powerW / 1000.0)
                powerSuffix = "k\(suffix)"
            } else if d.powerW >= 100 {
                powerStr = String(format: "%.0f", d.powerW)
                powerSuffix = suffix
            } else {
                powerStr = String(format: "%.1f", d.powerW)
                powerSuffix = suffix
            }
            swrStr = String(format: "%.2f", d.swr)
            // dBW / dBm / |Z| / phase are formatted with one fewer
            // decimal here than the raw value would support — at the
            // LP-100A's noise floor these all wobble at the 0.05–0.1
            // level and showing every wobble buys nothing visible.
            // Quantising at format time stabilises the signature so
            // signature-equal frames skip the publish entirely.
            dbwStr = String(format: "%.0f", d.dbw.rounded())
            dbmStr = String(format: "%.0f", d.dbm.rounded())
            zStr = String(format: "%.0f Ω", d.zOhm.rounded())
            phaseStr = String(format: "%.0f°", d.phaseDeg.rounded())
            range = d.range
            mode = d.mode
            alarmSetpoint = d.alarmSetpoint
            alarmTripped = d.alarmTripped
            callsign = d.callsign

            let pwrScale = RangeScale.max(for: d.range)
            powerBarBucket = pwrScale > 0
                ? Int((d.powerW / pwrScale * 100).rounded())
                : 0
            let swrFrac = (d.swr - 1.0) / (SWRScale.max - 1.0)
            swrBarBucket = Int((swrFrac * 100).rounded())
        }
    }

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
        // Reset so the first frame of a fresh connection always
        // publishes (no stale signature carries across reconnects).
        lastPublishedSignature = nil
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
        // Source-level dedup: skip the @Published mutation entirely if
        // none of the displayed values would change. SwiftUI never gets
        // invalidated for noise-floor wobble that rounds to the same
        // formatted strings + 1 %-quantized bargraph buckets. This is
        // dramatically cheaper than letting the view subtree's
        // `Equatable.equatable()` discover the same fact downstream.
        let sig = PublishSignature(p)
        lastPublishAt = Date()
        if sig == lastPublishedSignature { return }
        lastPublishedSignature = sig
        snapshot = p
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
