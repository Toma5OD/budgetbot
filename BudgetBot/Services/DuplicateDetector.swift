import Foundation

/// Pure, deterministic, fully tested. Given a draft and the set of already-saved
/// transactions, returns the IDs of likely duplicates so the Review screen can
/// flag (and the user can un-tick) them before commit.
///
/// Match rules:
///   - Date within ±3 days
///   - Amount sign matches and abs value within 1% (min ε 0.01)
///   - Payee normalised (lowercased + alphanumerics only) matches
struct DuplicateDetector {

    struct Existing: Identifiable {
        let id: UUID
        let date: Date
        let amount: Decimal
        let payee: String
    }

    let dateWindow: TimeInterval
    let amountTolerancePct: Decimal

    init(dateWindowDays: Int = 3, amountTolerancePct: Decimal = 0.01) {
        self.dateWindow = TimeInterval(dateWindowDays) * 24 * 60 * 60
        self.amountTolerancePct = amountTolerancePct
    }

    func duplicates(for draft: ExtractedDraft, against existing: [Existing]) -> [UUID] {
        let dPayee = Self.normalise(draft.payee)
        let dAmt = Self.absDecimal(draft.amount)
        guard dAmt > 0 else { return [] }

        return existing.compactMap { row in
            // Date window
            guard abs(row.date.timeIntervalSince(draft.date)) <= dateWindow else { return nil }
            // Sign match
            guard (row.amount < 0) == (draft.amount < 0) else { return nil }
            // Amount within tolerance
            let eAmt = Self.absDecimal(row.amount)
            let tol = max(dAmt * amountTolerancePct, Decimal(string: "0.01")!)
            guard Self.absDecimal(eAmt - dAmt) <= tol else { return nil }
            // Payee normalised match
            guard Self.normalise(row.payee) == dPayee else { return nil }
            return row.id
        }
    }

    // MARK: - Helpers (also used by tests)

    static func normalise(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
    }

    static func absDecimal(_ d: Decimal) -> Decimal {
        d < 0 ? -d : d
    }
}
