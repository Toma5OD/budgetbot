import Foundation
import Security

/// Tiny Keychain wrapper for storing the user's AI API key and Apple user id.
/// Items are scoped to this app's keychain access group.
enum KeychainKey: String {
    case anthropicAPIKey = "com.budgetbot.anthropicAPIKey"
    case appleUserID     = "com.budgetbot.appleUserID"
    case googleUserID    = "com.budgetbot.googleUserID"

    // Optional cloud transcription providers for dictation (Settings →
    // Dictation). On-device is the default and needs no key.
    case openAIKey       = "com.budgetbot.openAIKey"
    case geminiKey       = "com.budgetbot.geminiKey"

    // GoCardless Bank Account Data — the PSD2 aggregator powering
    // bank sync. Each user creates their own free-tier account at
    // bankaccountdata.gocardless.com and pastes both secrets here;
    // we exchange them for short-lived access + refresh tokens that
    // we also cache so the access token survives app restarts.
    case goCardlessSecretID     = "com.budgetbot.goCardlessSecretID"
    case goCardlessSecretKey    = "com.budgetbot.goCardlessSecretKey"
    case goCardlessAccessToken  = "com.budgetbot.goCardlessAccessToken"
    case goCardlessRefreshToken = "com.budgetbot.goCardlessRefreshToken"
    /// ISO8601 string — when the cached access token expires. Saves
    /// us a pre-emptive refresh on every call.
    case goCardlessAccessExpiry = "com.budgetbot.goCardlessAccessExpiry"
}

struct KeychainService {
    static let shared = KeychainService()

    func set(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encoding
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func get(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case encoding
        case status(OSStatus)
    }
}
