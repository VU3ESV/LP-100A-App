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
    /// Shown in the meter pane and the Connect sheet; set by a proxy 401, cleared once frames flow.
    @Published var lastConnectError: String?
    /// Username of the proxy login stored in the Keychain (read without the secret), or `nil`.
    @Published var proxyLoginUsername: String?

    /// True once the user has entered a server URL — drives whether the
    /// connection sheet opens automatically on launch.
    var hasConfiguredServer: Bool { Self.configuredServerURL(serverURLString) != nil }

    /// The server a saved "serverURL" preference points at, or `nil` when nothing usable is
    /// configured: empty, or no host (`"localhost:8088"` parses as scheme-only). The one rule
    /// shared by every entry point that connects on launch — the standalone window's
    /// bootstrap, `LP100APlugin.activate()` and the hosted `HostedRootView` — so all three
    /// behave alike.
    nonisolated static func configuredServerURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return nil }
        return url
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
    /// Bumped by every start()/stop(). A start() that is still awaiting the server when a
    /// newer start()/stop() happens sees a changed value and gives up instead of finishing.
    private var startGeneration = 0
    private var configClient: ConfigClient?
    private var listenTask: Task<Void, Never>?

    /// In-memory copy of the Keychain proxy login, read at connect time once per server URL —
    /// not per reconnect or frame. Save / Remove replace it directly.
    private var proxyCredentials: ProxyCredentials?
    private var proxyCredentialsSource: ProxyCredentialsSource = .unread
    private enum ProxyCredentialsSource: Equatable {
        case unread
        case keychain(URL)   // read for this server URL
        case saved           // set by Save / Remove; adopted by the next connection
    }

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

    deinit {
        // A replaced model (hosted scene rebuilt) must not leave its socket streaming into a
        // stream nobody reads.
        listenTask?.cancel()
        publishTask?.cancel()
        if let ws { Task { await ws.stop() } }
    }

    // MARK: - Connection management

    func start(serverURL: URL) async {
        log.debug("Starting against \(serverURL.absoluteString, privacy: .public)")
        // Idempotent: a second start() (window re-shown, hosted scene rebuilt, .task re-run)
        // replaces the previous client instead of leaving it connected as a zombie.
        await stop()
        // The awaits below can take a full URLSession timeout when the saved server is
        // unreachable. If the operator reconnects elsewhere meanwhile (reconnect() → stop()
        // + start()), this stale attempt must not finish by installing its own WSClient over
        // the live one and cancelling the live listen task.
        startGeneration &+= 1
        let generation = startGeneration
        serverURLString = serverURL.absoluteString
        lastConnectError = nil
        let credentials = await proxyCredentials(for: serverURL)
        guard generation == startGeneration else { return }
        let cfg = ConfigClient(baseURL: serverURL, credentials: credentials)
        configClient = cfg

        // Bootstrap from /api/config (best-effort). A proxy 401 is surfaced; the WebSocket
        // below then keeps retrying slowly until the login is fixed.
        var server: ServerConfig?
        var level: LogLevelConfig?
        var authError: ProxyAuthError?
        do {
            server = try await cfg.fetchConfig()
        } catch let error as ProxyAuthError {
            authError = error
        } catch {}
        if authError == nil { level = try? await cfg.fetchLogLevel() }
        guard generation == startGeneration else {
            log.debug("start(\(serverURL.absoluteString, privacy: .public)) superseded — dropping")
            return
        }
        if let server {
            let supported = server.views.filter { ["normal", "vector"].contains($0) }
            views = supported.isEmpty ? ["normal", "vector"] : supported
            allowControl = server.allowControl
        }
        if let level { serverLogLevel = level.level }
        if let authError { lastConnectError = authError.localizedDescription }

        let ws = WSClient(baseURL: serverURL, credentials: credentials)
        self.ws = ws
        await ws.start()
        listenTask?.cancel()
        let events = ws.events
        listenTask = Task { [weak self] in
            for await event in events {
                // Re-acquire per event so a replaced model can be released between frames.
                guard let self else { return }
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
        startGeneration &+= 1   // invalidate any start() still awaiting the server
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
        var probe = URLRequest(url: url.appendingPathComponent("/healthz"))
        let sentCredentials = ProxyAuth.authorize(&probe, with: await proxyCredentials(for: url))
        do {
            let (_, resp) = try await URLSession.shared.data(for: probe)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return .ok
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let authError = ProxyAuthError(httpStatus: status, credentialsSent: sentCredentials) {
                return .failure(authError.summary)
            }
            return .failure("Server returned non-2xx")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Proxy login (Keychain)

    /// The proxy login to send to `url`. Never touches the Keychain for http/ws URLs (nothing
    /// would be sent); otherwise reads it once per server URL, off the main actor because the
    /// read can wait on a Keychain prompt.
    private func proxyCredentials(for url: URL) async -> ProxyCredentials? {
        guard ProxyAuth.allowsCredentials(for: url) else { return nil }
        switch proxyCredentialsSource {
        case .saved:
            proxyCredentialsSource = .keychain(url)
        case .keychain(let loadedFor) where loadedFor == url:
            break
        default:
            let loaded = await Task.detached { ProxyKeychain.load() }.value
            // A Save / Remove that landed while the Keychain was being read wins.
            if proxyCredentialsSource != .saved { proxyCredentials = loaded }
            proxyCredentialsSource = .keychain(url)
        }
        return proxyCredentials
    }

    /// Refresh `proxyLoginUsername` from the Keychain without reading the secret (no prompt).
    func refreshProxyLoginStatus() async {
        proxyLoginUsername = await Task.detached { ProxyKeychain.storedUsername() }.value
    }

    enum ProxyLoginError: LocalizedError {
        case invalidUsername, emptyPassword
        var errorDescription: String? {
            switch self {
            case .invalidUsername: return "Enter a username without a colon."
            case .emptyPassword: return "Enter the password."
            }
        }
    }

    /// Save the proxy login to the Keychain (update, else add). The next connection attempt
    /// uses it; nothing is reconnected here.
    func saveProxyLogin(username: String, password: String) async throws {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !user.contains(":") else { throw ProxyLoginError.invalidUsername }
        guard !password.isEmpty else { throw ProxyLoginError.emptyPassword }
        let credentials = ProxyCredentials(username: user, password: password)
        try await Task.detached { try ProxyKeychain.save(credentials) }.value
        await useProxyCredentials(credentials)
        proxyLoginUsername = user
    }

    func removeProxyLogin() async throws {
        try await Task.detached { try ProxyKeychain.remove() }.value
        await useProxyCredentials(nil)
        proxyLoginUsername = nil
    }

    private func useProxyCredentials(_ credentials: ProxyCredentials?) async {
        proxyCredentials = credentials
        proxyCredentialsSource = .saved
        await ws?.setCredentials(credentials)
        await configClient?.setCredentials(credentials)
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
        do {
            serverLogLevel = try await configClient.setLogLevel(level).level
        } catch let error as ProxyAuthError {
            lastConnectError = error.localizedDescription
        } catch {}
    }

    // MARK: - Event handling

    private func handle(event: WSClient.Event) async {
        switch event {
        case .stateChanged(let s):
            connection = s
            if s == .connected { lastConnectError = nil }
        case .authFailed(let error):
            lastConnectError = error.localizedDescription
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
