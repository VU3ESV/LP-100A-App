import Foundation

// HTTP Basic auth for an authenticating TLS reverse proxy in front of the server
// (e.g. Caddy on the Pi). The proxy answers 401 to any request without a valid
// `Authorization` header, including the WebSocket upgrade. The login lives in the
// Keychain (see ProxyKeychain); this file is the pure part: when to attach it, how to
// encode it, and what a 401 means.

/// A proxy username + password. Never logged or displayed.
struct ProxyCredentials: Equatable {
    var username: String
    var password: String

    /// `Basic base64(username:password)` (RFC 7617, UTF-8).
    var basicAuthorization: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}

enum ProxyAuth {
    /// Credentials may only travel over TLS. Over `http`/`ws` they would cross the LAN in
    /// clear, so they are never attached there, even when a login is stored.
    static func allowsCredentials(for url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https", "wss": return true
        default: return false
        }
    }

    /// The `Authorization` header value for a request to `url`, or `nil` when nothing may be
    /// sent: no credentials, or a scheme other than `https`/`wss`.
    static func authorizationHeader(for url: URL, credentials: ProxyCredentials?) -> String? {
        guard let credentials, allowsCredentials(for: url) else { return nil }
        return credentials.basicAuthorization
    }

    /// Attach the `Authorization` header to `request` when `authorizationHeader` allows it.
    /// Returns whether it was attached (a later 401 then means "rejected", not "required").
    @discardableResult
    static func authorize(_ request: inout URLRequest, with credentials: ProxyCredentials?) -> Bool {
        guard let url = request.url,
              let value = authorizationHeader(for: url, credentials: credentials) else { return false }
        request.setValue(value, forHTTPHeaderField: "Authorization")
        return true
    }
}

/// A 401 from the proxy, on the WebSocket upgrade or on an HTTP call.
enum ProxyAuthError: Error, Equatable, LocalizedError {
    /// No credentials were sent (none stored, or the URL isn't https).
    case loginRequired
    /// Credentials were sent and the proxy refused them.
    case loginRejected

    /// Maps an HTTP status to a proxy-login error; `nil` for anything but 401.
    init?(httpStatus: Int, credentialsSent: Bool) {
        guard httpStatus == 401 else { return nil }
        self = credentialsSent ? .loginRejected : .loginRequired
    }

    /// One-line form for tight spots (the Connect sheet's Test connection label).
    var summary: String {
        switch self {
        case .loginRequired: return "Proxy login required (401)"
        case .loginRejected: return "Proxy login rejected (401)"
        }
    }

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return "Proxy login required (HTTP 401). Save a username and password under Proxy login in the connection settings; they are only sent to https:// servers."
        case .loginRejected:
            return "Proxy login rejected (HTTP 401). Check the username and password saved under Proxy login in the connection settings."
        }
    }
}
