import Foundation

// Thin REST helpers for /api/config and /api/log-level. The server treats
// log-level as in-memory state; resets on restart. Behind the authenticating proxy
// every request carries the proxy login (https only, see ProxyAuth); a 401 throws
// ProxyAuthError.
struct ServerConfig: Decodable, Equatable {
    var views: [String]
    var allowControl: Bool

    enum CodingKeys: String, CodingKey {
        case views
        case allowControl = "allow_control"
    }
}

struct LogLevelConfig: Codable, Equatable {
    var level: String
}

actor ConfigClient {
    private var baseURL: URL
    private var credentials: ProxyCredentials?
    private let session: URLSession

    init(baseURL: URL, credentials: ProxyCredentials? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
    }

    func setBaseURL(_ url: URL) {
        baseURL = url
    }

    func setCredentials(_ credentials: ProxyCredentials?) {
        self.credentials = credentials
    }

    func fetchConfig() async throws -> ServerConfig {
        try await get(path: "/api/config")
    }

    func fetchLogLevel() async throws -> LogLevelConfig {
        try await get(path: "/api/log-level")
    }

    func setLogLevel(_ level: String) async throws -> LogLevelConfig {
        try await postJSON(path: "/api/log-level", body: LogLevelConfig(level: level))
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let sentCredentials = ProxyAuth.authorize(&req, with: credentials)
        let (data, resp) = try await session.data(for: req)
        try checkOK(resp, sentCredentials: sentCredentials)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<Body: Encodable, R: Decodable>(path: String, body: Body) async throws -> R {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let sentCredentials = ProxyAuth.authorize(&req, with: credentials)
        let (data, resp) = try await session.data(for: req)
        try checkOK(resp, sentCredentials: sentCredentials)
        return try JSONDecoder().decode(R.self, from: data)
    }

    private func checkOK(_ resp: URLResponse, sentCredentials: Bool) throws {
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if let authError = ProxyAuthError(httpStatus: http.statusCode, credentialsSent: sentCredentials) {
            throw authError
        }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}
