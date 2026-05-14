import Foundation
import AuthenticationServices

/// GoCardless Bank Account Data — formerly Nordigen — is the free PSD2
/// aggregator we target for IE + UK at launch.
///
/// Architecture choice: each user creates their own free-tier account
/// at <https://bankaccountdata.gocardless.com> and pastes their Secret
/// ID + Secret Key. We exchange those for short-lived JWTs and use them
/// to drive the read-only Account Information API. Two reasons we don't
/// bundle a single set of credentials:
///   1. Anyone shipping a decompilable iOS binary with credentials in
///      it deserves the bill they get when those credentials leak.
///   2. The free tier is per-integrator (100 requisitions/month).
///      Sharing one quota across all our users would saturate fast.
///
/// Mirrors the [GoCardless Bank Account Data API docs](https://developer.gocardless.com/bank-account-data/overview).
public struct GoCardlessBankSyncProvider: BankSyncProvider {

    public let displayName = "GoCardless"
    public var isConfigured: Bool {
        let kc = KeychainService.shared
        return (kc.get(.goCardlessSecretID)?.isEmpty == false)
            && (kc.get(.goCardlessSecretKey)?.isEmpty == false)
    }

    /// Callback URL the user is bounced back to after consent. ASWebAuth
    /// captures any URL with this scheme.
    static let callbackURLScheme = "budgetbot"
    static let redirectURL = "budgetbot://oauth/callback"

    private let api = GoCardlessAPI()

    public init() {}

    // MARK: - BankSyncProvider

    public func connect(institution: BankInstitution) async throws -> BankConnection {
        // 1. Ask GC to create a requisition (returns a hosted consent
        //    link the user opens in the bank's app/web flow).
        let req = try await api.createRequisition(
            institutionID: institution.id,
            redirect: Self.redirectURL
        )
        // 2. Hand the link to ASWebAuthenticationSession. The session
        //    completes when GC redirects back to our scheme.
        try await openConsentFlow(url: req.link)
        // 3. Once the user finishes, GC has linked the accounts. Re-read
        //    the requisition to harvest them.
        let linked = try await api.requisition(id: req.id)
        guard !linked.accounts.isEmpty else {
            throw BankSyncError.authenticationFailed
        }
        var accountInfos: [BankAccountInfo] = []
        for accountID in linked.accounts {
            let details = try? await api.accountDetails(id: accountID)
            let balances = try? await api.accountBalances(id: accountID)
            let bal = balances?.balances.first?.balanceAmount.amount
                .flatMap { Decimal(string: $0) }
            accountInfos.append(BankAccountInfo(
                id: accountID,
                displayName: details?.account?.name ?? institution.displayName,
                kindRaw: details?.account?.cashAccountType ?? "current",
                currency: details?.account?.currency ?? "EUR",
                balance: bal,
                mask: details?.account?.iban.map { String($0.suffix(4)) }
            ))
        }
        return BankConnection(
            id: req.id,
            institution: institution,
            connectedAt: .now,
            accounts: accountInfos
        )
    }

    public func availableInstitutions(country: String) async throws -> [BankInstitution] {
        let raw = try await api.institutions(country: country)
        return raw.map { inst in
            BankInstitution(
                id: inst.id,
                displayName: inst.name,
                country: country,
                logoURL: inst.logo.flatMap { URL(string: $0) }
            )
        }
    }

    public func connections() async throws -> [BankConnection] {
        let reqs = try await api.requisitions()
        var out: [BankConnection] = []
        for r in reqs where r.status == "LN" {
            // GoCardless institution ids are "INSTNAME_XX" where XX is
            // the ISO country code. Fall back to IE if we can't parse.
            let country = String(r.institution_id.suffix(2)).uppercased()
            guard let inst = try? await api.institutions(country: country)
                                            .first(where: { $0.id == r.institution_id })
            else { continue }
            let infos: [BankAccountInfo] = await accountInfos(for: r.accounts)
            out.append(BankConnection(
                id: r.id,
                institution: BankInstitution(
                    id: inst.id, displayName: inst.name,
                    country: country,
                    logoURL: inst.logo.flatMap { URL(string: $0) }),
                connectedAt: ISO8601DateFormatter().date(from: r.created) ?? .now,
                accounts: infos
            ))
        }
        return out
    }

    public func transactions(account: BankAccountID, since cursor: String?)
        async throws -> (txs: [BankTransactionRaw], nextCursor: String?) {

        // GoCardless doesn't expose a true cursor; we ask for a
        // date range. The "cursor" we hand back is an ISO date string —
        // the most recent posted date in the response — so the next
        // call pulls only what arrived after.
        let cal = Calendar(identifier: .gregorian)
        let fromDate: Date
        if let cursor, let d = ISO8601DateFormatter().date(from: cursor) {
            fromDate = d
        } else {
            // First pull: back-fill 90 days.
            fromDate = cal.date(byAdding: .day, value: -90, to: .now) ?? .now
        }
        let resp = try await api.accountTransactions(
            id: account,
            from: fromDate
        )
        let raws: [BankTransactionRaw] = resp.transactions.booked.map { gc in
            let amount = Decimal(string: gc.transactionAmount.amount) ?? 0
            let merchant = gc.creditorName ?? gc.debtorName
            let date = ISO8601DateFormatter.dayOnly.date(from: gc.bookingDate) ?? .now
            let posted = gc.valueDate.flatMap { ISO8601DateFormatter.dayOnly.date(from: $0) }
            return BankTransactionRaw(
                id: gc.transactionId
                    ?? gc.internalTransactionId
                    ?? UUID().uuidString,
                accountID: account,
                date: date,
                postedAt: posted,
                amount: amount,
                currency: gc.transactionAmount.currency,
                merchant: merchant,
                description: gc.remittanceInformationUnstructured
                    ?? gc.remittanceInformationStructured
                    ?? merchant
                    ?? "Bank transaction",
                categoryHint: gc.merchantCategoryCode
            )
        }
        let next = raws.map(\.date).max()
            .map { ISO8601DateFormatter().string(from: $0) }
        return (raws, next)
    }

    public func disconnect(_ connectionID: BankConnectionID) async throws {
        try? await api.deleteRequisition(id: connectionID)
    }

    // MARK: - Private helpers

    @MainActor
    private func openConsentFlow(url consentURL: String) async throws {
        guard let url = URL(string: consentURL) else {
            throw BankSyncError.unknown("Invalid consent URL")
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.callbackURLScheme
            ) { _, error in
                if let nsErr = error as? NSError,
                   nsErr.domain == ASWebAuthenticationSessionError.errorDomain,
                   nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    cont.resume(throwing: BankSyncError.userCancelled)
                } else if let error {
                    cont.resume(throwing: BankSyncError.unknown(error.localizedDescription))
                } else {
                    cont.resume()
                }
            }
            session.presentationContextProvider = AuthSessionAnchor.shared
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                cont.resume(throwing: BankSyncError.unknown("Couldn't start auth session"))
            }
        }
    }

    private func accountInfos(for accountIDs: [String]) async -> [BankAccountInfo] {
        var out: [BankAccountInfo] = []
        for id in accountIDs {
            let details = try? await api.accountDetails(id: id)
            let balances = try? await api.accountBalances(id: id)
            let bal = balances?.balances.first?.balanceAmount.amount
                .flatMap { Decimal(string: $0) }
            out.append(BankAccountInfo(
                id: id,
                displayName: details?.account?.name ?? "Account",
                kindRaw: details?.account?.cashAccountType ?? "current",
                currency: details?.account?.currency ?? "EUR",
                balance: bal,
                mask: details?.account?.iban.map { String($0.suffix(4)) }
            ))
        }
        return out
    }
}

/// Presentation anchor for ASWebAuthenticationSession. Just hands back
/// the key window. Lives at file scope because the session retains it.
@MainActor
final class AuthSessionAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthSessionAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? ASPresentationAnchor()
    }
}

// `ISO8601DateFormatter.dayOnly` is already defined elsewhere in the
// app (see `Utilities`-level extensions) — reusing that one.
