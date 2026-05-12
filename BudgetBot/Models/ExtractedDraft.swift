import Foundation

/// The shape returned by the AI when it parses a receipt / invoice / description.
/// Not persisted — feeds the Review screen which then writes Transactions.
struct ExtractedDraft: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Decimal             // signed: negative for expense, positive for income
    var currency: String
    var payee: String
    var note: String?
    var suggestedCategory: String?  // free-form name; mapped to a Category by the reviewer
    var accountHint: String?        // free-form account name the AI thinks this belongs to
    var lineItems: [LineItem]
    var confidence: Double          // 0..1

    struct LineItem: Codable, Hashable, Identifiable {
        var id = UUID()
        var description: String
        var amount: Decimal
    }
}

/// Wire-format the AI must emit. Decoded then converted to `ExtractedDraft`.
struct ExtractedDraftWire: Codable {
    let date: String?            // ISO 8601 yyyy-MM-dd
    let amount: Double           // signed
    let currency: String?
    let payee: String?
    let note: String?
    let suggested_category: String?
    let account_hint: String?
    let line_items: [LineItemWire]?
    let confidence: Double?

    struct LineItemWire: Codable {
        let description: String
        let amount: Double
    }
}

/// AI's recommendation envelope.
struct RecommendationWire: Codable {
    let kind: String             // "silly" | "savings" | "general"
    let title: String
    let body: String
    let estimated_monthly_savings: Double?
}

struct RecommendationsWire: Codable {
    let recommendations: [RecommendationWire]
}

/// Minimal description of accounts we send to the AI so it can hint which
/// account a transaction belongs to without us leaking IDs.
struct AccountContext: Codable {
    let name: String
    let kind: String
    let currency: String
}
