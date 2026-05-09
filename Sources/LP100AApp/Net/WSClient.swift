import Foundation

// Single-connection WebSocket client with auto-reconnect and heartbeat
// watchdog. The server sends a snapshot on connect; clients only need to
// listen to the inbound stream.
actor WSClient {
    enum ConnectionState: Equatable {
        case disconnected
        case reconnecting
        case connected
    }

    enum Event {
        case stateChanged(ConnectionState)
        case frame(ServerFrame)
        case parseError(String)
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession
    private var baseURL: URL
    private var state: ConnectionState = .disconnected
    private var backoffMs: UInt64 = 500
    private let maxBackoffMs: UInt64 = 10_000
    private let heartbeatTimeoutNs: UInt64 = 4_000_000_000
    private var lastFrameAt: ContinuousClock.Instant = .now
    private var receiveTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private let continuation: AsyncStream<Event>.Continuation
    nonisolated let events: AsyncStream<Event>
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // Coalesce telemetry frames at the receive side so JSONDecoder runs
    // at most ~5 Hz regardless of the meter's poll cadence (typically
    // ~10 Hz for LP-100A). Heartbeat/status/ack frames are always
    // decoded — they're rare or already infrequent.
    private let telemetryMinInterval: TimeInterval = 0.2
    private var lastTelemetryDecodedAt: Date = .distantPast
    // `"power_w"` is unique to telemetry frames (the meter snapshot
    // body). Heartbeat / status / ack don't carry it. Cheap substring
    // scan — no JSON decode needed to discriminate.
    private static let telemetryHint = "\"power_w\""

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let (stream, cont) = AsyncStream.makeStream(of: Event.self)
        self.events = stream
        self.continuation = cont
    }

    func setBaseURL(_ url: URL) async {
        guard url != baseURL else { return }
        baseURL = url
        await reconnectNow()
    }

    func start() {
        guard receiveTask == nil else { return }
        Task { await self.connectLoop() }
    }

    func stop() {
        receiveTask?.cancel()
        watchdogTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        receiveTask = nil
        watchdogTask = nil
        emit(.stateChanged(.disconnected))
    }

    func send(_ frame: ClientFrame) async throws {
        guard let task else { throw URLError(.networkConnectionLost) }
        let data = try encoder.encode(frame)
        try await task.send(.data(data))
    }

    private func reconnectNow() async {
        task?.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()
        watchdogTask?.cancel()
        task = nil
        receiveTask = nil
        watchdogTask = nil
        backoffMs = 500
        Task { await self.connectLoop() }
    }

    private func connectLoop() async {
        emit(.stateChanged(.reconnecting))
        let wsURL = wsURL(from: baseURL)
        let new = session.webSocketTask(with: wsURL)
        task = new
        new.resume()
        lastFrameAt = .now
        // Don't claim .connected until we receive the first frame (the
        // server pushes a snapshot on accept). See handle(message:).
        backoffMs = 500
        startReceive(on: new)
        startWatchdog()
    }

    private func startReceive(on task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let msg = try await task.receive()
                    await self?.handle(message: msg)
                } catch {
                    await self?.handleDisconnect()
                    return
                }
            }
        }
    }

    private func startWatchdog() {
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.checkHeartbeat()
            }
        }
    }

    private func checkHeartbeat() async {
        let elapsed = lastFrameAt.duration(to: .now)
        if elapsed > .nanoseconds(Int(heartbeatTimeoutNs)), state == .connected {
            emit(.stateChanged(.reconnecting))
            await handleDisconnect()
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
        lastFrameAt = .now
        // First inbound frame confirms the WebSocket handshake actually
        // completed; until now we were optimistically calling ourselves
        // "connected" right after task.resume().
        if state != .connected { emit(.stateChanged(.connected)) }
        let data: Data?
        let raw: String?
        switch message {
        case .data(let d):
            data = d
            raw = String(data: d, encoding: .utf8)
        case .string(let s):
            data = s.data(using: .utf8)
            raw = s
        @unknown default:
            data = nil
            raw = nil
        }
        guard let data else { return }

        // Telemetry frames dominate the wire (~10 Hz) and are ~250 bytes
        // each; status / ack / heartbeat are rare and tiny. Drop
        // telemetry frames inside the throttle window without paying
        // for JSON decode. One cheap substring scan, no parse — the
        // server emits keys in alphabetical order so `"power_w"` lands
        // inside the embedded `data` object near the front of the wire
        // bytes.
        if let raw, raw.contains(Self.telemetryHint) {
            let now = Date()
            if now.timeIntervalSince(lastTelemetryDecodedAt) < telemetryMinInterval {
                return
            }
            lastTelemetryDecodedAt = now
        }

        do {
            let frame = try decoder.decode(ServerFrame.self, from: data)
            emit(.frame(frame))
        } catch {
            emit(.parseError(error.localizedDescription))
        }
    }

    private func handleDisconnect() async {
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        receiveTask?.cancel()
        watchdogTask?.cancel()
        receiveTask = nil
        watchdogTask = nil
        emit(.stateChanged(.disconnected))
        let delay = backoffMs
        backoffMs = min(backoffMs * 2, maxBackoffMs)
        try? await Task.sleep(nanoseconds: delay * 1_000_000)
        if !Task.isCancelled {
            await connectLoop()
        }
    }

    private func emit(_ event: Event) {
        if case .stateChanged(let s) = event { state = s }
        continuation.yield(event)
    }

    private func wsURL(from base: URL) -> URL {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        switch comps.scheme {
        case "https": comps.scheme = "wss"
        default: comps.scheme = "ws"
        }
        comps.path = (comps.path.hasSuffix("/") ? comps.path : comps.path + "/") + "ws"
        comps.path = comps.path.replacingOccurrences(of: "//ws", with: "/ws")
        return comps.url ?? base
    }
}
