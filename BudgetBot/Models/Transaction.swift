import Foundation
import SwiftData

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// Signed amount. Negative = money out (expense), Positive = money in (income).
    var amount: Decimal
    var currency: String
    var payee: String
    var note: String?
    var confirmed: Bool
    var aiExtracted: Bool
    var createdAt: Date

    // MARK: - FX snapshot
    //
    // Captured at commit time so historical Net Worth is correct even years
    // later when ECB rates have drifted. `nil` for rows where currency == base
    // at commit time (no conversion needed) or for rows committed before this
    // field existed (SwiftData backfills nil; aggregations fall back to live
    // FX in that case).

    /// 1 unit of `currency` was worth this many units of `fxBaseCurrency` at commit time.
    var fxRateToBase: Decimal?
    /// User's base currency at the moment this tx was committed.
    var fxBaseCurrency: String?

    @Relationship var account: Account?
    @Relationship var category: TxCategory?
    @Relationship(deleteRule: .cascade) var attachment: Attachment?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        amount: Decimal = 0,
        currency: String = "USD",
        payee: String = "",
        note: String? = nil,
        confirmed: Bool = false,
        aiExtracted: Bool = false,
        fxRateToBase: Decimal? = nil,
        fxBaseCurrency: String? = nil,
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
        self.fxRateToBase = fxRateToBase
        self.fxBaseCurrency = fxBaseCurrency
        self.account = account
        self.category = category
        self.attachment = attachment
        self.createdAt = createdAt
    }

    var isExpense: Bool { amount < 0 }
    var absAmount: Decimal { amount < 0 ? -amount : amount }

    /// Convert this transaction's amount to `base`.
    ///
    /// Order of preference:
    ///   1. If we snapshotted FX at commit and base hasn't changed → use snapshot.
    ///   2. Else use the live-rate fallback (`liveConvert`).
    ///   3. If `liveConvert` is unavailable (e.g. tests), return raw amount.
    func amountInBase(_ base: String, liveConvert: (Decimal, String, String) -> Decimal) -> Decimal {
        if let rate = fxRateToBase,
           let snapBase = fxBaseCurrency,
           snapBase.uppercased() == base.uppercased() {
            return amount * rate
        }
        return liveConvert(amount, currency, base)
    }
}
