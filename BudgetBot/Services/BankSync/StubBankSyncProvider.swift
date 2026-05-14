import Foundation

/// No-op provider used until the real Tink/TrueLayer/Plaid integration
/// is wired with credentials. Returns `isConfigured = false` and throws
/// `notConfigured` from every call. The Settings UI renders a "coming
/// soon" state when this is the active provider.
///
/// Keep this class even after a real provider lands — it's useful as
/// the default in tests and as a fallback when credentials are
/// temporarily missing.
public struct StubBankSyncProvider: BankSyncProvider {
    public let displayName: String
    public let isConfigured: Bool = false

    /// Country this provider would target if/when configured. Used by
    /// the UI to filter the "which country are you in" picker.
    public let country: String

    public init(name: String, country: String) {
        self.displayName = name
        self.country = country
    }

    public func connect(institution: BankInstitution) async throws -> BankConnection {
        throw BankSyncError.notConfigured(provider: displayName)
    }

    public func availableInstitutions(country: String) async throws -> [BankInstitution] {
        throw BankSyncError.notConfigured(provider: displayName)
    }

    public func connections() async throws -> [BankConnection] { [] }

    public func transactions(account: BankAccountID, since cursor: String?)
        async throws -> (txs: [BankTransactionRaw], nextCursor: String?) {
        throw BankSyncError.notConfigured(provider: displayName)
    }

    public func disconnect(_ connectionID: BankConnectionID) async throws {
        // No-op — nothing to disconnect.
    }
}
