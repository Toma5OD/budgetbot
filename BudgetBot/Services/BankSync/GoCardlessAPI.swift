import Foundation

/// HTTP client + Codable wire types for GoCardless Bank Account Data.
/// Single source of truth for every call we make against
/// `bankaccountdata.gocardless.com/api/v2`.
///
/// Token handling: access token (24h) + refresh token (30d) — both
/// cached in Keychain. We pre-emptively refresh when the cached expiry
/// is within 60s of now; on a 401 we refresh once and retry. If both
/// tokens are gone, we re-auth with the stored secrets.
struct GoCardlessAPI {

    private let baseURL = URL(string: "https://bankaccountdata.gocardless.com/api/v2")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Wire types

    struct TokenResponse: Codable {
        let access: String
        let access_expires: Int   // seconds
        let refresh: String
        let refresh_expires: Int
    }

    struct Institution: Codable, Identifiable {
        let id: String
        let name: String
        let bic: String?
        let transaction_total_days: String?
        let countries: [String]?
        let logo: String?
    }

    struct RequisitionCreate: Codable {
        let id: String
        let created: String
        let link: String
        let institution_id: String
        let status: String
    }

    struct Requisition: Codable, Identifiable {
        let id: String
        let created: String
        let status: String
        let accounts: [String]
        let institution_id: String
    }

    struct RequisitionList: Codable {
        let results: [Requisition]
    }

    struct AccountDetails: Codable {
        let account: AccountInner?
        struct AccountInner: Codable {
            let resourceId: String?
            let iban: String?
            let currency: String?
            let name: String?
            let product: String?
            let cashAccountType: String?
            let ownerName: String?
        }
    }

    struct Balances: Codable {
        let balances: [Balance]
        struct Balance: Codable {
            let balanceAmount: Amount
            let balanceType: String?
        }
        struct Amount: Codable {
            let amount: String?
            let currency: String?
        }
    }

    struct TransactionsResponse: Codable {
        let transactions: Buckets
        struct Buckets: Codable {
            let booked: [Tx]
            let pending: [Tx]?
        }
        struct Tx: Codable {
            let transactionId: String?
            let internalTransactionId: String?
            let bookingDate: String
            let valueDate: String?
            let transactionAmount: Amount
            let creditorName: String?
            let debtorName: String?
            let remittanceInformationUnstructured: String?
            let remittanceInformationStructured: String?
            let merchantCategoryCode: String?
        }
        struct Amount: Codable {
            let amount: String
            let currency: String
        }
    }

    // MARK: - Calls

    func institutions(country: String) async throws -> [Institution] {
        var components = URLComponents(url: baseURL.appendingPathComponent("institutions/"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "country", value: country)]
        let req = try await authedRequest(url: components.url!, method: "GET", body: nil)
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode([Institution].self, from: data)
    }

    func createRequisition(institutionID: String, redirect: String) async throws -> RequisitionCreate {
        let body: [String: Any] = [
            "redirect": redirect,
            "institution_id": institutionID,
            "user_language": "EN"
        ]
        let req = try await authedRequest(
            url: baseURL.appendingPathComponent("requisitions/"),
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(RequisitionCreate.self, from: data)
    }

    func requisitions() async throws -> [Requisition] {
        let req = try await authedRequest(
            url: baseURL.appendingPathComponent("requisitions/"),
            method: "GET", body: nil
        )
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(RequisitionList.self, from: data).results
    }

    func requisition(id: String) async throws -> Requisition {
        let req = try await authedRequest(
            url: baseURL.appendingPathComponent("requisitions/\(id)/"),
            method: "GET", body: nil
        )
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(Requisition.self, from: data)
    }

    func deleteRequisition(id: String) async throws {
        let req = try await authedRequest(
            url: baseURL.appendingPathComponent("requisitions/\(id)/"),
            method: "DELETE", body: nil
        )
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
    }

    func accountDetails(id: String) async throws -> AccountDetails {
        let req = try await authedRequest(
            url: baseURL.appendingPathComponent("accounts/\(id)/details/"),
            method: "GET", body: nil
        )
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(AccountDetails.self, from: data)
    }

    func accountBalances(id: String) async throws -> Balances {
        let req = try await authedRequest(
            url: baseURL.appendingPathComponent("accounts/\(id)/balances/"),
            method: "GET", body: nil
        )
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(Balances.self, from: data)
    }

    func accountTransactions(id: String, from: Date) async throws -> TransactionsResponse {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        var components = URLComponents(
            url: baseURL.appendingPathComponent("accounts/\(id)/transactions/"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "date_from", value: df.string(from: from))
        ]
        let req = try await authedRequest(url: components.url!, method: "GET", body: nil)
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(TransactionsResponse.self, from: data)
    }

    // MARK: - Auth

    private func authedRequest(url: URL, method: String, body: Data?) async throws -> URLRequest {
        let token = try await currentAccessToken()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func currentAccessToken() async throws -> String {
        let kc = KeychainService.shared
        if let cached = kc.get(.goCardlessAccessToken),
           let expiryString = kc.get(.goCardlessAccessExpiry),
           let expiry = ISO8601DateFormatter().date(from: expiryString),
           expiry.timeIntervalSinceNow > 60 {
            return cached
        }
        // Cached token missing or near-expiry — refresh, else re-auth.
        if let refresh = kc.get(.goCardlessRefreshToken) {
            if let access = try? await exchangeRefresh(token: refresh) {
                return access
            }
        }
        return try await freshAuth()
    }

    private func freshAuth() async throws -> String {
        let kc = KeychainService.shared
        guard let secretID = kc.get(.goCardlessSecretID),
              let secretKey = kc.get(.goCardlessSecretKey) else {
            throw BankSyncError.notConfigured(provider: "GoCardless")
        }
        let body: [String: String] = ["secret_id": secretID, "secret_key": secretKey]
        var req = URLRequest(url: baseURL.appendingPathComponent("token/new/"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        try storeToken(token)
        return token.access
    }

    private func exchangeRefresh(token refresh: String) async throws -> String? {
        var req = URLRequest(url: baseURL.appendingPathComponent("token/refresh/"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh": refresh])
        let (data, resp) = try await session.data(for: req)
        try? validate(resp, data: data)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        struct RefreshResp: Codable { let access: String; let access_expires: Int }
        let r = try JSONDecoder().decode(RefreshResp.self, from: data)
        let expiry = Date().addingTimeInterval(TimeInterval(r.access_expires))
        let kc = KeychainService.shared
        try? kc.set(r.access, for: .goCardlessAccessToken)
        try? kc.set(ISO8601DateFormatter().string(from: expiry),
                    for: .goCardlessAccessExpiry)
        return r.access
    }

    private func storeToken(_ t: TokenResponse) throws {
        let kc = KeychainService.shared
        try kc.set(t.access, for: .goCardlessAccessToken)
        try kc.set(t.refresh, for: .goCardlessRefreshToken)
        let expiry = Date().addingTimeInterval(TimeInterval(t.access_expires))
        try kc.set(ISO8601DateFormatter().string(from: expiry),
                   for: .goCardlessAccessExpiry)
    }

    // MARK: - Validation

    private func validate(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw BankSyncError.network(underlying: "Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300: return
        case 401:
            throw BankSyncError.authenticationFailed
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw BankSyncError.rateLimited(retryAfter: retry)
        case 404:
            throw BankSyncError.institutionUnavailable
        default:
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw BankSyncError.network(underlying: "HTTP \(http.statusCode): \(body)")
        }
    }
}
