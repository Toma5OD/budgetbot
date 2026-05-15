import Foundation

/// Renders a list of `Transaction`s as a CSV blob. Used by Settings →
/// Data → "Export transactions" — primarily a tax-season escape hatch
/// so the user can hand the file to an accountant or import it
/// somewhere else.
///
/// Format is deliberately conservative:
///   - RFC-4180-ish: comma-separated, double-quoted fields when a field
///     contains a comma / quote / newline, doubled inner quotes.
///   - One row per `Transaction` — splits are summarised as their
///     parent's category (cleanest export shape; users who split
///     things rarely want them flattened in CSV).
///   - Header row in plain English.
///
/// Returns the encoded UTF-8 data ready for `UIActivityViewController`
/// or `.fileExporter`.
enum CSVExporter {

    static func transactionsCSV(
        _ transactions: [Transaction],
        baseCurrency: String? = nil
    ) -> Data {
        let header = [
            "Date", "Payee", "Category", "Account",
            "Amount", "Currency", "Payment method", "Note",
            "Confirmed", "Rating", "Recurring", "External ID"
        ]
        var rows: [[String]] = [header]
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        let sorted = transactions.sorted { $0.date > $1.date }
        for tx in sorted {
            rows.append([
                df.string(from: tx.date),
                tx.payee,
                tx.category?.name ?? "",
                tx.account?.name ?? "",
                amountString(tx.amount),
                tx.currency,
                tx.paymentDescription,
                tx.note ?? "",
                tx.confirmed ? "yes" : "no",
                tx.hindsightRating.map(String.init) ?? "",
                tx.recurringRuleID != nil ? "yes" : "no",
                tx.externalID ?? ""
            ])
        }
        let csv = rows.map(rowString).joined(separator: "\n")
        return Data(csv.utf8)
    }

    /// Suggested file name for the share sheet. Date-stamped so multiple
    /// exports don't collide in the user's Files app.
    static func suggestedFilename(date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "budgetbot-transactions-\(f.string(from: date)).csv"
    }

    // MARK: - Helpers

    private static func amountString(_ d: Decimal) -> String {
        let ns = d as NSDecimalNumber
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")   // dot-decimal for tools
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f.string(from: ns) ?? "\(d)"
    }

    private static func rowString(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    private static func escape(_ s: String) -> String {
        let needs = s.contains(",") || s.contains("\"") || s.contains("\n")
        guard needs else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
