import Foundation
import SwiftData

/// Converts `BankTransactionRaw` rows from a `BankSyncProvider` into our
/// SwiftData `Transaction` records. Encapsulates two things that are
/// easy to get wrong:
///   - **Dedup** — by `externalID` so re-pulling the same window is a
///     no-op. The aggregator's transaction id is the source of truth;
///     when it's absent we fall back to a `payee + date + amount`
///     fingerprint.
///   - **Enrichment** — runs descriptions through `PayeeNormaliser` to
///     clean up `TESCO STORES *4242 STRASBOURG` → `Tesco`, then through
///     `CaptureCategoryResolver` to attach a category (or create one).
@MainActor
enum BankTransactionImporter {

    /// Result of an import pass — useful for the UI to surface
    /// "imported N, skipped M (dupes)" feedback.
    struct ImportResult: Equatable {
        var inserted: Int = 0
        var updated: Int = 0
        var skippedDuplicate: Int = 0
        var totalProcessed: Int { inserted + updated + skippedDuplicate }
    }

    /// Imports the supplied raw rows into the given context, using
    /// `account` as the local Account for ownership. Saves once at the
    /// end. Caller is responsible for finding/creating the Account that
    /// matches the GoCardless account id (we don't know the user's
    /// preferred naming).
    @discardableResult
    static func importRows(
        _ rows: [BankTransactionRaw],
        into account: Account,
        context: ModelContext,
        existingCategories: [TxCategory]? = nil
    ) throws -> ImportResult {
        var result = ImportResult()

        // Pre-fetch existing externalIDs so the dedup loop stays O(N).
        let allExisting = try context.fetch(FetchDescriptor<Transaction>())
        let byExternalID: [String: Transaction] = Dictionary(
            uniqueKeysWithValues: allExisting.compactMap { tx in
                tx.externalID.map { ($0, tx) }
            }
        )

        let categories = existingCategories
            ?? (try? context.fetch(FetchDescriptor<TxCategory>()))
            ?? []
        let existingPayeeKeys = Set(allExisting.map { PayeeNormaliser.key($0.payee) })

        for raw in rows {
            // Same external id already present? Update in place (covers
            // late-posting status changes, amount corrections) and move
            // on.
            if let existing = byExternalID[raw.id] {
                existing.amount = raw.amount
                existing.date = raw.date
                if let merchant = raw.merchant, !merchant.isEmpty {
                    let key = PayeeNormaliser.key(merchant)
                    existing.payee = PayeeNormaliser.canonical(
                        forKey: key,
                        in: Array(existingPayeeKeys.union([key])),
                        fallback: merchant
                    )
                }
                result.updated += 1
                continue
            }

            // No external id match — soft dedup by payee+date+amount
            // (banks occasionally re-issue a tx with a new id).
            let merchant = raw.merchant ?? raw.description
            let key = PayeeNormaliser.key(merchant)
            let canonicalPayee = PayeeNormaliser.canonical(
                forKey: key,
                in: allExisting.map(\.payee),
                fallback: merchant
            )
            let softDup = allExisting.contains { tx in
                PayeeNormaliser.key(tx.payee) == key
                    && Calendar.current.isDate(tx.date, inSameDayAs: raw.date)
                    && tx.amount == raw.amount
                    && tx.externalID == nil   // only fuzzy-match against manual entries
            }
            if softDup {
                result.skippedDuplicate += 1
                continue
            }

            // Categorise. First try a case-insensitive name match on
            // the bank's category hint — banks vary wildly in how
            // useful that is. If that misses, fall back to our own
            // MerchantClassifier so a Domino's row gets "Dining" /
            // Insomnia gets "Coffee" / a Long Hall round gets
            // "Alcohol" — even if the bank's hint was useless. We
            // deliberately don't auto-create categories from bank
            // hints (MCC codes are too vague to enrich the catalog).
            let category: TxCategory? = raw.categoryHint
                .flatMap { hint in
                    categories.first { $0.name.localizedCaseInsensitiveCompare(hint) == .orderedSame }
                }
                ?? classifierCategory(for: canonicalPayee, from: categories)
            let tx = Transaction(
                date: raw.date,
                amount: raw.amount,
                currency: raw.currency,
                payee: canonicalPayee,
                note: raw.description == canonicalPayee ? nil : raw.description,
                confirmed: true,
                aiExtracted: false,
                externalID: raw.id,
                account: account,
                category: category
            )
            context.insert(tx)
            result.inserted += 1
        }

        try context.save()
        return result
    }

    /// Fallback category resolver — when the bank's category hint
    /// missed (or didn't ship at all), we look at the merchant name
    /// itself. Maps the behavioural buckets `MerchantClassifier`
    /// recognises to our default category catalogue:
    ///
    ///   - `.coffee`   → "Coffee"
    ///   - `.alcohol`  → "Alcohol"
    ///   - `.fastFood` → "Dining"   (no separate fast-food category)
    ///
    /// Premium / value retail aren't bucketable to a single category
    /// (could be groceries, clothing, electronics…), so we leave them
    /// uncategorised and let the user assign.
    private static func classifierCategory(
        for payee: String,
        from categories: [TxCategory]
    ) -> TxCategory? {
        if MerchantClassifier.isCoffee(payee) {
            return categories.first { $0.name == "Coffee" }
        }
        if MerchantClassifier.isAlcohol(payee: payee, categoryName: nil) {
            return categories.first { $0.name == "Alcohol" }
        }
        if MerchantClassifier.isFastFood(payee) {
            return categories.first { $0.name == "Dining" }
        }
        return nil
    }
}
