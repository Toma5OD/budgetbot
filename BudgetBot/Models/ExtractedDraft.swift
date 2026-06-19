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
    /// Category name the AI picked from the existing list. Preferred whenever any
    /// existing category fits.
    var suggestedCategory: String?
    /// Set only when the AI determined NO existing category fits. The commit
    /// pipeline will create a new TxCategory with this name unless it can
    /// fuzzy-match an existing one.
    var newCategory: String?
    var accountHint: String?
    var paymentMethod: PaymentMethod = .unknown
    /// "Visa", "Mastercard", "Amex", "Discover", "Other" — when the receipt
    /// or statement printed the card brand. Nil otherwise.
    var cardBrand: String?
    /// 4-digit string for the partial card number when the receipt shows it
    /// ("**** 4242", "Card ending 4242", etc).
    var cardLast4: String?
    var lineItems: [LineItem]
    var confidence: Double

    enum PaymentMethod: String, Codable, Hashable {
        case cash
        case card
        case unknown
    }

    struct LineItem: Codable, Hashable, Identifiable {
        var id = UUID()
        var description: String
        var amount: Decimal
        var category: String? = nil
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
    let new_category: String?
    let account_hint: String?
    let payment_method: String?  // "cash" | "card" | "unknown"
    let card_brand: String?      // "Visa" | "Mastercard" | "Amex" | "Discover" | "Other"
    let card_last4: String?      // 4-digit string
    let line_items: [LineItemWire]?
    let confidence: Double?

    struct LineItemWire: Codable {
        let description: String
        let amount: Double
        let category: String?
    }
}

// MARK: - AI itemisation (describe a charge → line items)

/// One AI-derived line item for an existing charge. `amount` is the
/// positive line total (quantity × unit price); the caller applies the
/// transaction's sign when writing it as a `Split`.
struct ItemisedLine: Identifiable, Hashable {
    var id = UUID()
    var description: String
    var quantity: Int
    var amount: Decimal
    var category: String?

    /// Per-unit price, for display ("€2.00 each").
    var unitAmount: Decimal {
        quantity > 1 ? amount / Decimal(quantity) : amount
    }
}

/// The outcome of reconciling AI line items against a known charge
/// total — honest about whether the described items actually account
/// for the whole charge.
struct ItemisationResult: Hashable {
    var lines: [ItemisedLine]
    var status: Status

    enum Status: Hashable {
        /// Items add up to the total (within rounding).
        case balanced
        /// Items fall short; `remainder` was added as an "Unaccounted" line.
        case under(remainder: Decimal)
        /// Items exceed the total by `excess` — needs the user's call.
        case over(excess: Decimal)
    }

    var sum: Decimal { lines.reduce(Decimal(0)) { $0 + $1.amount } }
}

/// Wire shape the AI emits for itemisation.
struct ItemisationWire: Codable {
    let items: [Item]
    struct Item: Codable {
        let description: String
        let quantity: Int?
        let amount: Double
        let category: String?
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
