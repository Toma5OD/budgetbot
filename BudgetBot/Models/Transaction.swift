import Foundation
import SwiftData

/// A money-movement event. Industry-standard personal-finance shape — one row
/// per thing that happened, with optional `splits` when a single payment
/// needs to be allocated across multiple categories.
///
/// `category` is the headline category for the whole transaction. When the
/// transaction is split, `category` is ignored at aggregation time and each
/// `Split.category` contributes its own slice (see
/// `Transaction.categorisedAmounts(in:liveConvert:)`).
@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// Signed total in `currency`. Negative = money OUT, positive = money IN.
    var amount: Decimal
    var currency: String
    var payee: String
    var note: String?
    var confirmed: Bool
    var aiExtracted: Bool
    var createdAt: Date

    var paymentMethodRaw: String

    // FX snapshot — captured at commit time so historical Net Worth survives
    // ECB-rate drift.
    var fxRateToBase: Decimal?
    var fxBaseCurrency: String?

    /// Pointer to the recurring rule we detected this transaction as part of.
    /// `nil` for one-off purchases.
    var recurringRuleID: UUID?

    @Relationship var account: Account?
    @Relationship var category: TxCategory?
    @Relationship(deleteRule: .cascade) var attachment: Attachment?
    @Relationship(deleteRule: .cascade, inverse: \Split.transaction)
    var splits: [Split] = []

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
        fxRateToBase: Decimal? = nil,
        fxBaseCurrency: String? = nil,
        recurringRuleID: UUID? = nil,
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
        self.fxRateToBase = fxRateToBase
        self.fxBaseCurrency = fxBaseCurrency
        self.recurringRuleID = recurringRuleID
        self.account = account
        self.category = category
        self.attachment = attachment
        self.createdAt = createdAt
    }

    // MARK: - Payment method

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

    // MARK: - Derived

    var isExpense: Bool { amount < 0 }
    var absAmount: Decimal { amount < 0 ? -amount : amount }
    var isSplit: Bool { !splits.isEmpty }

    /// Convert this transaction's amount to `base`. Prefers the snapshot
    /// taken at commit time; falls back to live FX when the user has changed
    /// base currency since.
    func amountInBase(_ base: String, liveConvert: (Decimal, String, String) -> Decimal) -> Decimal {
        if let rate = fxRateToBase,
           let snapBase = fxBaseCurrency,
           snapBase.uppercased() == base.uppercased() {
            return amount * rate
        }
        return liveConvert(amount, currency, base)
    }

    /// One row per category contribution. For non-split transactions this is
    /// a single (amount, category); for split transactions one entry per
    /// split. Used by analytics, subscriptions, drilldowns.
    struct CategorisedSlice {
        let description: String   // payee for non-split, item description for splits
        let amount: Decimal       // in base currency
        let category: TxCategory?
    }

    func categorisedSlices(in base: String, liveConvert: (Decimal, String, String) -> Decimal) -> [CategorisedSlice] {
        if splits.isEmpty {
            return [CategorisedSlice(
                description: payee,
                amount: amountInBase(base, liveConvert: liveConvert),
                category: category
            )]
        }
        return splits.map { s in
            let raw = s.amount
            let inBase: Decimal = {
                if let rate = fxRateToBase,
                   let snapBase = fxBaseCurrency,
                   snapBase.uppercased() == base.uppercased() {
                    return raw * rate
                }
                return liveConvert(raw, currency, base)
            }()
            return CategorisedSlice(
                description: s.itemDescription,
                amount: inBase,
                category: s.category
            )
        }
    }
}

/// One row of a multi-category transaction. Only exists when the user (or AI)
/// has chosen to split a single payment across categories. Equivalent to
/// YNAB's "split" or Copilot's "split transaction" sub-row.
@Model
final class Split {
    @Attribute(.unique) var id: UUID
    var itemDescription: String
    /// Signed amount in the parent transaction's `currency`.
    var amount: Decimal
    var quantity: Int
    var createdAt: Date

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

    /// Convenience accessors so split rows can render without dereferencing
    /// the parent every time.
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
