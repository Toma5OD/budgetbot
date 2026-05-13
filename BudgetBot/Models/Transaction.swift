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

    // FX snapshot — captured at commit time.
    var fxRateToBase: Decimal?
    var fxBaseCurrency: String?

    var recurringRuleID: UUID?

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
