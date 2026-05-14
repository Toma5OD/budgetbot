import Foundation
import SwiftData

/// A money-movement event. Industry-standard personal-finance shape — one row
/// per thing that happened, with optional `splits` when a single payment
/// needs to be allocated across multiple categories.
@Model
final class Transaction {
    var id: UUID = UUID()
    var date: Date = Date.now
    /// Signed total in `currency`. Negative = money OUT, positive = money IN.
    var amount: Decimal = 0
    var currency: String = "EUR"
    var payee: String = ""
    var note: String?
    var confirmed: Bool = false
    var aiExtracted: Bool = false
    var createdAt: Date = Date.now

    var paymentMethodRaw: String = PaymentMethod.unknown.rawValue
    /// "Visa", "Mastercard", "Amex", "Discover", "Other" when known.
    var cardBrand: String?
    /// Last 4 digits of the card used when the receipt revealed them.
    var cardLast4: String?

    // FX snapshot — captured at commit time.
    var fxRateToBase: Decimal?
    var fxBaseCurrency: String?

    var recurringRuleID: UUID?

    /// User-flagged "Hall of Shame" purchase — drives the Regrets screen.
    /// All three fields default so the SwiftData/CloudKit schema migrates
    /// transparently for users on older builds.
    var isRegret: Bool = false
    /// One of `Transaction.regretEmojis` when set. Free-form but the UI only
    /// surfaces a curated chip list.
    var regretEmoji: String?
    /// Optional one-liner from the user explaining why this stung.
    var regretNote: String?

    /// 1-5 star rating the user gave this purchase *in hindsight* through
    /// the rate-your-purchases game. `nil` = not rated yet. The intent is
    /// retrospective signal — "knowing what you know now, was it worth
    /// it?" — distinct from the `isRegret` boolean flag (which is more
    /// "this stung enough to nominate for the Hall of Shame").
    var hindsightRating: Int?
    /// When the rating was last set or changed. Lets us surface
    /// "rated 3 days ago" labels and keep an audit trail if we ever
    /// expose rating history.
    var hindsightRatedAt: Date?

    @Relationship var account: Account?
    @Relationship var category: TxCategory?
    @Relationship(deleteRule: .cascade) var attachment: Attachment?
    /// Optional to satisfy CloudKit. Use the `.splits ?? []` pattern at reads.
    @Relationship(deleteRule: .cascade, inverse: \Split.transaction)
    var splits: [Split]?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        amount: Decimal = 0,
        currency: String = "EUR",
        payee: String = "",
        note: String? = nil,
        confirmed: Bool = false,
        aiExtracted: Bool = false,
        paymentMethod: PaymentMethod = .unknown,
        cardBrand: String? = nil,
        cardLast4: String? = nil,
        fxRateToBase: Decimal? = nil,
        fxBaseCurrency: String? = nil,
        recurringRuleID: UUID? = nil,
        isRegret: Bool = false,
        regretEmoji: String? = nil,
        regretNote: String? = nil,
        hindsightRating: Int? = nil,
        hindsightRatedAt: Date? = nil,
        account: Account? = nil,
        category: TxCategory? = nil,
        attachment: Attachment? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.currency = currency
        self.payee = payee
        self.note = note
        self.confirmed = confirmed
        self.aiExtracted = aiExtracted
        self.paymentMethodRaw = paymentMethod.rawValue
        self.cardBrand = cardBrand
        self.cardLast4 = cardLast4
        self.fxRateToBase = fxRateToBase
        self.fxBaseCurrency = fxBaseCurrency
        self.recurringRuleID = recurringRuleID
        self.isRegret = isRegret
        self.regretEmoji = regretEmoji
        self.regretNote = regretNote
        self.hindsightRating = hindsightRating
        self.hindsightRatedAt = hindsightRatedAt
        self.account = account
        self.category = category
        self.attachment = attachment
        self.createdAt = createdAt
    }

    enum PaymentMethod: String, Codable, CaseIterable {
        case cash, card, unknown
        var displayName: String {
            switch self { case .cash: "Cash"; case .card: "Card"; case .unknown: "—" }
        }
        var systemImage: String {
            switch self {
            case .cash:    "banknote.fill"
            case .card:    "creditcard.fill"
            case .unknown: "questionmark.circle"
            }
        }
    }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .unknown }
        set { paymentMethodRaw = newValue.rawValue }
    }

    /// Human-readable payment label combining method + brand + last-4.
    /// Examples: "Visa ••4242", "Mastercard", "Cash", "Card ••4242", "Card", "—".
    var paymentDescription: String {
        switch paymentMethod {
        case .cash:
            return "Cash"
        case .unknown:
            if let brand = cardBrand, let last4 = cardLast4 { return "\(brand) ••\(last4)" }
            if let brand = cardBrand { return brand }
            return "—"
        case .card:
            if let brand = cardBrand, let last4 = cardLast4 { return "\(brand) ••\(last4)" }
            if let brand = cardBrand { return brand }
            if let last4 = cardLast4 { return "Card ••\(last4)" }
            return "Card"
        }
    }

    /// Curated emoji chips used by the Hall of Shame picker. Keep first;
    /// users see them in this order. Anything outside the list is allowed in
    /// data but won't be offered in the picker.
    static let regretEmojis: [(String, String)] = [
        ("🤡", "Clown moment"),
        ("🍻", "Drunk buy"),
        ("🛍️", "Retail therapy"),
        ("🍕", "Late-night order"),
        ("💸", "Money pit"),
        ("🥲", "Should've known"),
        ("🎰", "Lost a bet"),
        ("🚕", "Could've walked")
    ]

    // MARK: - Derived

    var isExpense: Bool { amount < 0 }
    var absAmount: Decimal { amount < 0 ? -amount : amount }

    /// Non-optional accessor for code readability. Use this instead of
    /// `splits ?? []`.
    var splitItems: [Split] { splits ?? [] }
    var isSplit: Bool { !splitItems.isEmpty }

    func amountInBase(_ base: String, liveConvert: (Decimal, String, String) -> Decimal) -> Decimal {
        if let rate = fxRateToBase,
           let snapBase = fxBaseCurrency,
           snapBase.uppercased() == base.uppercased() {
            return amount * rate
        }
        return liveConvert(amount, currency, base)
    }

    struct CategorisedSlice {
        let description: String
        let amount: Decimal
        let category: TxCategory?
    }

    func categorisedSlices(in base: String, liveConvert: (Decimal, String, String) -> Decimal) -> [CategorisedSlice] {
        let s = splitItems
        if s.isEmpty {
            return [CategorisedSlice(
                description: payee,
                amount: amountInBase(base, liveConvert: liveConvert),
                category: category
            )]
        }
        return s.map { split in
            let inBase: Decimal = {
                if let rate = fxRateToBase,
                   let snapBase = fxBaseCurrency,
                   snapBase.uppercased() == base.uppercased() {
                    return split.amount * rate
                }
                return liveConvert(split.amount, currency, base)
            }()
            return CategorisedSlice(
                description: split.itemDescription,
                amount: inBase,
                category: split.category
            )
        }
    }
}

@Model
final class Split {
    var id: UUID = UUID()
    var itemDescription: String = ""
    var amount: Decimal = 0
    var quantity: Int = 1
    var createdAt: Date = Date.now

    @Relationship var category: TxCategory?
    @Relationship var transaction: Transaction?

    init(
        id: UUID = UUID(),
        description: String,
        amount: Decimal,
        quantity: Int = 1,
        category: TxCategory? = nil,
        transaction: Transaction? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemDescription = description
        self.amount = amount
        self.quantity = quantity
        self.category = category
        self.transaction = transaction
        self.createdAt = createdAt
    }

    var date: Date { transaction?.date ?? createdAt }
    var currency: String { transaction?.currency ?? "EUR" }
    var payee: String { transaction?.payee ?? "" }
    var account: Account? { transaction?.account }

    func amountInBase(_ base: String, liveConvert: (Decimal, String, String) -> Decimal) -> Decimal {
        if let tx = transaction,
           let rate = tx.fxRateToBase,
           let snapBase = tx.fxBaseCurrency,
           snapBase.uppercased() == base.uppercased() {
            return amount * rate
        }
        return liveConvert(amount, currency, base)
    }
}
