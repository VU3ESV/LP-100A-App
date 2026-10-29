import XCTest
import Network
@testable import LP100AApp

/// The proxy login (HTTP Basic, for an authenticating TLS reverse proxy) may only travel over
/// TLS, must be encoded per RFC 7617, and a 401 must say whether a login was sent. Credentials
/// here are injected test values: the tests never touch the Keychain.
final class ProxyAuthTests: XCTestCase {
    private let creds = ProxyCredentials(username: "Aladdin", password: "open sesame")

    // MARK: - Encoding

    func testBasicAuthorizationMatchesRFC7617() {
        // RFC 7617 §2 and §2.1 examples.
        XCTAssertEqual(creds.basicAuthorization, "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
        XCTAssertEqual(ProxyCredentials(username: "test", password: "123£").basicAuthorization,
                       "Basic dGVzdDoxMjPCow==")
    }

    func testBasicAuthorizationDecodesBackToUserColonPassword() throws {
        let value = ProxyCredentials(username: "operator", password: "p:ss wörd").basicAuthorization
        XCTAssertTrue(value.hasPrefix("Basic "))
        let data = try XCTUnwrap(Data(base64Encoded: String(value.dropFirst("Basic ".count))))
        XCTAssertEqual(String(data: data, encoding: .utf8), "operator:p:ss wörd")
    }

    // MARK: - https/wss only

    func testHeaderAttachedForHTTPSAndWSS() {
        for s in ["https://192.168.86.43:8088", "wss://192.168.86.43:8088/ws", "HTTPS://host:8088"] {
            XCTAssertEqual(ProxyAuth.authorizationHeader(for: URL(string: s)!, credentials: creds),
                           creds.basicAuthorization, s)
        }
    }

    func testHeaderNeverAttachedForPlainHTTPOrWS() {
        for s in ["http://192.168.86.43:8088", "ws://192.168.86.43:8088/ws", "HTTP://host:8088",
                  "ftp://host/"] {
            XCTAssertNil(ProxyAuth.authorizationHeader(for: URL(string: s)!, credentials: creds), s)
        }
    }

    func testNoHeaderWithoutCredentials() {
        XCTAssertNil(ProxyAuth.authorizationHeader(for: URL(string: "https://host:8088")!,
                                                   credentials: nil))
    }

    func testAuthorizeSetsHeaderOnlyForHTTPS() {
        var tls = URLRequest(url: URL(string: "https://host:8088/api/config")!)
        XCTAssertTrue(ProxyAuth.authorize(&tls, with: creds))
        XCTAssertEqual(tls.value(forHTTPHeaderField: "Authorization"), creds.basicAuthorization)

        var plain = URLRequest(url: URL(string: "http://host:8088/api/config")!)
        XCTAssertFalse(ProxyAuth.authorize(&plain, with: creds))
        XCTAssertNil(plain.value(forHTTPHeaderField: "Authorization"))
    }

    func testWebSocketUpgradeRequest() {
        let tls = WSClient.upgradeRequest(baseURL: URL(string: "https://192.168.86.43:8088")!,
                                          credentials: creds)
        XCTAssertEqual(tls.url?.absoluteString, "wss://192.168.86.43:8088/ws")
        XCTAssertEqual(tls.value(forHTTPHeaderField: "Authorization"), creds.basicAuthorization)
        XCTAssertNil(tls.value(forHTTPHeaderField: "Origin"), "the proxy 403s a mismatched Origin")

        let plain = WSClient.upgradeRequest(baseURL: URL(string: "http://192.168.86.43:8088/")!,
                                            credentials: creds)
        XCTAssertEqual(plain.url?.absoluteString, "ws://192.168.86.43:8088/ws")
        XCTAssertNil(plain.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - 401 mapping

    func test401MapsToRequiredOrRejected() {
        XCTAssertEqual(ProxyAuthError(httpStatus: 401, credentialsSent: false), .loginRequired)
        XCTAssertEqual(ProxyAuthError(httpStatus: 401, credentialsSent: true), .loginRejected)
        for status in [0, 101, 200, 403, 404, 500] {
            XCTAssertNil(ProxyAuthError(httpStatus: status, credentialsSent: true), "\(status)")
        }
    }

    func testErrorTextsAreDistinct() {
        let required = ProxyAuthError.loginRequired.localizedDescription
        let rejected = ProxyAuthError.loginRejected.localizedDescription
        XCTAssertTrue(required.hasPrefix("Proxy login required"))
        XCTAssertTrue(rejected.hasPrefix("Proxy login rejected"))
        XCTAssertNotEqual(ProxyAuthError.loginRequired.summary, ProxyAuthError.loginRejected.summary)
    }

    // MARK: - Against a local server that answers 401

    /// A plain-http server that requires a login: the stored login must not be sent, the
    /// upgrade's 401 surfaces as "required", and the client backs off instead of retrying
    /// after the usual 500 ms.
    func testWebSocket401OverPlainHTTPSendsNoCredentialsAndBacksOff() async throws {
        let server = try await UnauthorizedServer.start()
        defer { server.stop() }
        let client = WSClient(baseURL: URL(string: "http://127.0.0.1:\(server.port)")!,
                              credentials: creds, session: URLSession(configuration: .ephemeral))
        let failed = expectation(description: "auth failure surfaced")

        let collector = Task { () -> (attempts: Int, errors: [ProxyAuthError]) in
            var attempts = 0
            var errors: [ProxyAuthError] = []
            for await event in client.events {
                switch event {
                case .stateChanged(.reconnecting): attempts += 1
                case .authFailed(let e):
                    errors.append(e)
                    if errors.count == 1 { failed.fulfill() }
                default: break
                }
            }
            return (attempts, errors)
        }

        await client.start()
        await fulfillment(of: [failed], timeout: 8)
        try await Task.sleep(nanoseconds: 1_500_000_000)   // the normal first backoff is 500 ms
        await client.stop()
        collector.cancel()
        let result = await collector.value

        XCTAssertEqual(result.errors, [.loginRequired])
        XCTAssertEqual(result.attempts, 1, "a 401 must not be retried at the fast backoff")
        let request = server.receivedRequest.lowercased()
        XCTAssertTrue(request.hasPrefix("get /ws "), "expected the upgrade request")
        XCTAssertFalse(request.contains("\r\nauthorization:"), "login sent over plain ws")
        XCTAssertFalse(request.contains("\r\norigin:"), "no Origin header may be sent")
    }

    func testConfigClient401OverPlainHTTPThrowsRequiredAndSendsNoCredentials() async throws {
        let server = try await UnauthorizedServer.start()
        defer { server.stop() }
        let cfg = ConfigClient(baseURL: URL(string: "http://127.0.0.1:\(server.port)")!,
                               credentials: creds, session: URLSession(configuration: .ephemeral))
        do {
            _ = try await cfg.fetchConfig()
            XCTFail("expected a 401")
        } catch let error as ProxyAuthError {
            XCTAssertEqual(error, .loginRequired)
        }
        let request = server.receivedRequest.lowercased()
        XCTAssertTrue(request.hasPrefix("get /api/config "))
        XCTAssertFalse(request.contains("\r\nauthorization:"), "login sent over plain http")
    }
}

/// Accepts TCP connections on 127.0.0.1, records the first request and answers 401 the way
/// the proxy does.
private final class UnauthorizedServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var received = Data()
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    var receivedRequest: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: received, as: UTF8.self)
    }

    func stop() { listener.cancel() }

    static func start() async throws -> UnauthorizedServer {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        let ready = AsyncStream<UInt16>.makeStream()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port?.rawValue { ready.continuation.yield(port) }
                ready.continuation.finish()
            case .failed, .cancelled:
                ready.continuation.finish()
            default: break
            }
        }
        let box = ServerBox()
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                if let data { box.server?.record(data) }
                let reply = "HTTP/1.1 401 Unauthorized\r\n"
                    + "WWW-Authenticate: Basic realm=\"StationMonitor2\"\r\n"
                    + "Content-Length: 0\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(reply.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        listener.start(queue: .global())
        var port: UInt16 = 0
        for await p in ready.stream { port = p }
        guard port != 0 else { listener.cancel(); throw URLError(.cannotConnectToHost) }
        let server = UnauthorizedServer(listener: listener, port: port)
        box.server = server
        return server
    }

    private func record(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if received.isEmpty { received = data }
    }
}

private final class ServerBox: @unchecked Sendable {
    weak var server: UnauthorizedServer?
}
