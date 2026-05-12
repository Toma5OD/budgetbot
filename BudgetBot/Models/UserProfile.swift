import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var appleUserID: String
    var displayName: String?
    var email: String?
    /// Currency used by default when adding a new account / capturing a tx.
    var defaultCurrency: String
    /// Currency in which Net Worth, Analytics totals and budget are expressed.
    var baseCurrency: String
    var monthlyBudget: Decimal?
    var aiModel: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        appleUserID: String,
        displayName: String? = nil,
        email: String? = nil,
        defaultCurrency: String = "USD",
        baseCurrency: String? = nil,
        monthlyBudget: Decimal? = nil,
        aiModel: String = AIService.defaultModel,
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
        self.createdAt = createdAt
    }
}
