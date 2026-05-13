import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID = UUID()
    var appleUserID: String = ""
    var displayName: String?
    var email: String?
    /// Currency used by default when adding a new account / capturing a tx.
    var defaultCurrency: String = "EUR"
    /// Currency in which Net Worth, Analytics totals and budget are expressed.
    var baseCurrency: String = "EUR"
    var monthlyBudget: Decimal?
    var aiModel: String = "claude-sonnet-4-6"
    /// Which OAuth provider the user originally signed in with.
    /// Values: "apple", "google". Defaults to apple for legacy rows.
    var authProvider: String = "apple"
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        appleUserID: String,
        displayName: String? = nil,
        email: String? = nil,
        defaultCurrency: String = "USD",
        baseCurrency: String? = nil,
        monthlyBudget: Decimal? = nil,
        aiModel: String = AIService.defaultModel,
        authProvider: String = "apple",
        createdAt: Date = .now
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.email = email
        self.defaultCurrency = defaultCurrency
        self.baseCurrency = baseCurrency ?? defaultCurrency
        self.monthlyBudget = monthlyBudget
        self.aiModel = aiModel
        self.authProvider = authProvider
        self.createdAt = createdAt
    }
}
