import Foundation

/// Compiled into BOTH the BudgetBot app and the ShareExtension target.
/// Anything other than constants & pure data lives elsewhere.
enum SharedConfig {
    /// App Group container used to hand attachments from the Share Extension
    /// to the main app. MUST match the entitlement files.
    static let appGroupID = "group.com.budgetbot.shared"
}
