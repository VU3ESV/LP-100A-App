import XCTest
import Network
@testable import LP100AApp

/// WSClient has to keep retrying on its own. Its disconnect handler used to cancel the very
/// task it was running on before sleeping, so the sleep threw at once, `Task.isCancelled`
/// was true, and no retry ever ran: every connection got exactly one attempt. A plugin or app
/// launched before its server, or any later drop, stayed Offline until the operator pressed
/// Connect again.
final class WSClientReconnectTests: XCTestCase {

    /// Nothing listens on port 1, so each attempt is refused immediately. The client must
    /// come back for a second attempt after its first (500 ms) backoff, and must not claim
    /// `.connected` for a handshake that never completed.
    func testRetriesAfterRefusedConnection() async {
        let client = WSClient(baseURL: URL(string: "http://127.0.0.1:1")!)
        let secondAttempt = expectation(description: "second connect attempt")

        // Each attempt emits exactly one `.reconnecting` (from connectLoop); the failure
        // path emits nothing new while the state is already `.reconnecting`.
        let collector = Task { () -> (attempts: Int, claimedConnected: Bool) in
            var attempts = 0
            var claimedConnected = false
            for await event in client.events {
                guard case .stateChanged(let state) = event else { continue }
                if state == .connected { claimedConnected = true }
                if state == .reconnecting {
                    attempts += 1
                    if attempts == 2 { secondAttempt.fulfill() }
                }
            }
            return (attempts, claimedConnected)
        }

        await client.start()
        await fulfillment(of: [secondAttempt], timeout: 8)
        await client.stop()
        collector.cancel()   // ends the `for await` for this consumer
        let result = await collector.value

        XCTAssertGreaterThanOrEqual(result.attempts, 2,
                                    "WSClient never retried after a refused connection")
        XCTAssertFalse(result.claimedConnected,
                       "`.connected` must wait for the first inbound frame")
    }

    /// stop() must also drop a pending retry, or a client the operator disconnected (or a
    /// view model that was replaced) would quietly reconnect later.
    func testStopCancelsPendingRetry() async {
        let client = WSClient(baseURL: URL(string: "http://127.0.0.1:1")!)
        let firstFailure = expectation(description: "first attempt failed")

        let collector = Task { () -> Int in
            var attempts = 0
            var seenFailure = false
            for await event in client.events {
                guard case .stateChanged(let state) = event else { continue }
                if state == .reconnecting {
                    attempts += 1
                    // The attempt has failed once the task is gone; give URLSession a moment.
                    if attempts == 1, !seenFailure {
                        seenFailure = true
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        firstFailure.fulfill()
                    }
                }
            }
            return attempts
        }

        await client.start()
        await fulfillment(of: [firstFailure], timeout: 8)
        await client.stop()
        // Longer than the first backoff: a leaked retry would show up as a second attempt.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        collector.cancel()
        let attempts = await collector.value

        XCTAssertEqual(attempts, 1, "a stopped client must not retry")
    }

    /// A TCP listener that accepts but never answers the WebSocket handshake keeps `receive()`
    /// pending. stop() during that wait cancels the receive task; its error used to be treated
    /// as a drop, which (with retries working) scheduled a reconnect of a client nobody wanted.
    func testStopWhileHandshakePendingDoesNotReconnect() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        listener.newConnectionHandler = { conn in conn.start(queue: .global()) }   // accept, stay silent
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 5)
        defer { listener.cancel() }
        let port = try XCTUnwrap(listener.port?.rawValue)

        let client = WSClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        let collector = Task { () -> [WSClient.ConnectionState] in
            var states: [WSClient.ConnectionState] = []
            for await event in client.events {
                if case .stateChanged(let s) = event { states.append(s) }
            }
            return states
        }

        await client.start()
        try await Task.sleep(nanoseconds: 400_000_000)     // handshake pending, receive() waiting
        await client.stop()
        try await Task.sleep(nanoseconds: 1_200_000_000)   // longer than the first backoff
        collector.cancel()
        let states = await collector.value

        XCTAssertEqual(states, [.reconnecting, .disconnected],
                       "stop() must be final: nothing may follow .disconnected")
    }
}
