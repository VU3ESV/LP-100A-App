import Foundation
import Security

/// The proxy login in the login Keychain: a generic password with service `ShackProxy`
/// and the username as its account (what `security add-generic-password -s ShackProxy
/// -a operator -w` creates). Looked up by service alone, so the username comes from the
/// item. One login per Mac: saving under a new username replaces the old item.
///
/// These calls are synchronous and may block on a Keychain access prompt, so callers run
/// them off the main actor.
enum ProxyKeychain {
    static let service = "ShackProxy"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain: \(text)"
        }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service]
    }

    /// The stored login's username, without reading the secret (attributes only), so it
    /// never triggers a Keychain prompt. `nil` when no login is stored.
    static func storedUsername() -> String? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attrs = result as? [String: Any] else { return nil }
        return attrs[kSecAttrAccount as String] as? String
    }

    /// The stored login, or `nil` when there is none or it can't be read (e.g. the operator
    /// denied the Keychain prompt). Checks existence first so a Mac without a login is never
    /// prompted.
    static func load() -> ProxyCredentials? {
        guard storedUsername() != nil else { return nil }
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let account = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return ProxyCredentials(username: account, password: password)
    }

    /// Update the item for this username, else add it (replacing a login stored under a
    /// different username, since lookups are by service).
    static func save(_ credentials: ProxyCredentials) throws {
        var match = baseQuery
        match[kSecAttrAccount as String] = credentials.username
        let secret = Data(credentials.password.utf8)
        var status = SecItemUpdate(match as CFDictionary,
                                   [kSecValueData as String: secret] as CFDictionary)
        if status == errSecItemNotFound {
            try remove()
            var add = match
            add[kSecAttrLabel as String] = service
            add[kSecValueData as String] = secret
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Delete every `ShackProxy` item. No item is not an error.
    static func remove() throws {
        // The file-based keychain can delete one match per call; loop (bounded) until none.
        for _ in 0..<16 {
            let status = SecItemDelete(baseQuery as CFDictionary)
            if status == errSecItemNotFound { return }
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }
    }
}
