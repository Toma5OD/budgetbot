import Foundation

/// Open-banking provider abstraction. The whole point is to keep the
/// **app logic** independent of *which* aggregator we end up using
/// (Tink, TrueLayer, Plaid, Belvo, …) — when the procurement
/// conversation completes we plug a real implementation behind this
/// protocol and the rest of the app doesn't change.
///
/// Concrete providers should:
///   - keep tokens in Keychain, never UserDefaults
///   - normalise transactions to `BankTransactionRaw` (currency-
///     preserving, no FX) so the import pipeline doesn't need to
///     know about the provider's wire format
///   - never throw on transient network errors — translate them to
///     the `BankSyncError` cases so the UI can render usefully
public protocol BankSyncProvider: Sendable {
    /// Human-readable name for the Settings → Connect a bank row.
    var displayName: String { get }

    /// `true` only when the provider is wired with real credentials and
    /// can make live API calls. Stubs return `false`; the UI uses this
    /// to disable connect buttons and surface a "coming soon" message.
    var isConfigured: Bool { get }

    /// Kick off the user-facing OAuth / consent flow. The provider
    /// returns when the user finishes (or cancels). Token storage is
    /// the provider's responsibility.
    func connect(institution: BankInstitution) async throws -> BankConnection

    /// Read-only list of institutions the provider can connect to,
    /// scoped to a country.
    func availableInstitutions(country: String) async throws -> [BankInstitution]

    /// Already-connected institutions and their accounts.
    func connections() async throws -> [BankConnection]

    /// Fetch transactions on a specific connected account since
    /// `cursor` (an opaque per-account token returned by the previous
    /// pull). On first call pass `nil`. Returned cursor is whatever
    /// the provider wants — opaque to us.
    func transactions(account: BankAccountID, since cursor: String?)
        async throws -> (txs: [BankTransactionRaw], nextCursor: String?)

    /// Revoke + delete a connection (provider side + local). Should be
    /// idempotent.
    func disconnect(_ connectionID: BankConnectionID) async throws
}

// MARK: - Value types

public typealias BankConnectionID = String
public typealias BankAccountID = String

public struct BankInstitution: Hashable, Codable, Sendable, Identifiable {
    public let id: String           // provider-scoped, opaque
    public let displayName: String
    public let country: String      // ISO-3166-1 alpha-2
    public let logoURL: URL?
    public init(id: String, displayName: String, country: String, logoURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.country = country
        self.logoURL = logoURL
    }
}

public struct BankConnection: Identifiable, Hashable, Codable, Sendable {
    public let id: BankConnectionID
    public let institution: BankInstitution
    public let connectedAt: Date
    public let accounts: [BankAccountInfo]
    /// `true` when the bank's consent has expired (or the requisition
    /// went to a non-linked state). PSD2 caps active consents at 180
    /// days in EU/UK; we conservatively flag at 89 days so the user
    /// can renew before transactions stop arriving.
    public let needsReconnect: Bool

    public init(id: BankConnectionID, institution: BankInstitution,
                connectedAt: Date, accounts: [BankAccountInfo],
                needsReconnect: Bool = false) {
        self.id = id
        self.institution = institution
        self.connectedAt = connectedAt
        self.accounts = accounts
        self.needsReconnect = needsReconnect
    }
}

public struct BankAccountInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: BankAccountID
    public let displayName: String
    public let kindRaw: String      // "current" / "savings" / "credit" — provider-scoped
    public let currency: String
    public let balance: Decimal?
    public let mask: String?        // last-4 of the account / IBAN tail when supplied
    public init(id: BankAccountID, displayName: String, kindRaw: String,
                currency: String, balance: Decimal?, mask: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.kindRaw = kindRaw
        self.currency = currency
        self.balance = balance
        self.mask = mask
    }
}

/// One bank-supplied transaction, normalised. Provider-specific fields
/// go into `metadata`. Conversion to our SwiftData `Transaction` model
/// happens in the import pipeline once these reach the app.
public struct BankTransactionRaw: Identifiable, Hashable, Codable, Sendable {
    public let id: String                // provider-scoped, used for dedup
    public let accountID: BankAccountID
    public let date: Date
    public let postedAt: Date?
    /// Signed in `currency`. Negative = money OUT.
    public let amount: Decimal
    public let currency: String
    public let merchant: String?
    public let description: String
    public let categoryHint: String?     // provider's category guess
    public let metadata: [String: String]
    public init(id: String, accountID: BankAccountID, date: Date, postedAt: Date?,
                amount: Decimal, currency: String, merchant: String?,
                description: String, categoryHint: String? = nil,
                metadata: [String: String] = [:]) {
        self.id = id
        self.accountID = accountID
        self.date = date
        self.postedAt = postedAt
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.description = description
        self.categoryHint = categoryHint
        self.metadata = metadata
    }
}

// MARK: - Errors

public enum BankSyncError: LocalizedError, Sendable {
    case notConfigured(provider: String)
    case userCancelled
    case authenticationFailed
    case institutionUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case network(underlying: String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            return "\(provider) isn't configured yet. Tap to see what's missing."
        case .userCancelled:
            return "Connection cancelled."
        case .authenticationFailed:
            return "Your bank rejected the sign-in."
        case .institutionUnavailable:
            return "This bank isn't available right now. Try again later."
        case .rateLimited:
            return "Hit the bank API rate limit. Try again in a minute."
        case .network(let s):
            return "Network error: \(s)"
        case .unknown(let s):
            return s
        }
    }
}

// MARK: - Registry

/// Single source of truth for which provider the app is currently using.
/// Concrete providers register themselves at compile time; the active
/// one comes from `UserDefaults["BudgetBot.bankProvider"]`.
public enum BankSyncRegistry {
    /// All known providers, configured or not. Used to render the
    /// Settings picker. GoCardless is first because it's the only
    /// real implementation we currently ship — the others are stubs
    /// (the procurement track for Tink / TrueLayer / Plaid).
    public static var all: [any BankSyncProvider] = [
        GoCardlessBankSyncProvider(),
        StubBankSyncProvider(name: "Tink", country: "IE"),
        StubBankSyncProvider(name: "TrueLayer", country: "GB"),
        StubBankSyncProvider(name: "Plaid", country: "US")
    ]

    public static var active: any BankSyncProvider {
        let key = UserDefaults.standard.string(forKey: "BudgetBot.bankProvider")
        return all.first { $0.displayName == key } ?? all[0]
    }

    public static func setActive(_ name: String) {
        UserDefaults.standard.set(name, forKey: "BudgetBot.bankProvider")
    }
}
