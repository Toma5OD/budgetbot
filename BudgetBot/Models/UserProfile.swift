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
    /// YOLO mode: auto-commit AI-extracted drafts without per-batch review.
    /// Off by default — surfaces each batch in the notification center for
    /// the user to confirm.
    var yoloMode: Bool = false
    /// Critique mode: after the first AI extracts drafts, a second AI pass
    /// audits the result against the original receipts and applies
    /// corrections. Doubles per-batch API cost; off by default. Most of the
    /// time it returns "all good" and is a no-op; occasionally it catches a
    /// misread digit or a wrong category.
    var critiqueMode: Bool = false
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
        yoloMode: Bool = false,
        critiqueMode: Bool = false,
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
        self.yoloMode = yoloMode
        self.critiqueMode = critiqueMode
        self.createdAt = createdAt
    }
}
