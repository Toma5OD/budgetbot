import Foundation

/// Parses a quick free-text (or dictated) expense into a payee, amount,
/// and quantity — "haircut €30" → ("Haircut", 30, 1); "2 coffees for €13"
/// → ("Coffees", 13, 2). Pure and local: no AI, no network, no key, so
/// it's instant and works offline. Imperfect parses are fine — the user
/// edits afterwards.
struct QuickEntry: Equatable {
    var payee: String
    /// Positive magnitude. The caller applies the expense sign.
    var amount: Decimal
    var quantity: Int
    /// A date the user stated ("yesterday", "2 days ago"). Nil means the
    /// caller should use the current date + time.
    var date: Date?
}

enum QuickEntryParser {

    /// Returns nil when there's no usable amount in the text. `now` is the
    /// reference for relative dates (injectable for tests).
    static func parse(_ raw: String, now: Date = Date()) -> QuickEntry? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 0. Pull out any stated date ("yesterday", "2 days ago") and
        //    strip it so it doesn't pollute the payee.
        let (statedDate, dateStripped) = extractDate(from: trimmed, now: now)
        let text = dateStripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 1. Amount — prefer a currency-tagged number; else the largest
        //    bare number (a small leading number is usually a quantity).
        guard let amountHit = amount(in: text) else { return nil }

        // 2. Quantity — a small leading integer followed by a word, as
        //    long as it isn't the amount itself.
        let qty = leadingQuantity(in: text, excluding: amountHit)

        // 3. Payee — strip the amount token, a leading quantity, currency
        //    symbols and filler, then tidy up.
        let payee = cleanPayee(text, amountRange: amountHit.range, quantityRange: qty?.range)

        return QuickEntry(payee: payee.isEmpty ? "Expense" : payee,
                          amount: amountHit.value,
                          quantity: max(1, qty?.value ?? 1),
                          date: statedDate)
    }

    // MARK: - Date

    /// Recognises a few common relative dates and returns the resolved
    /// date plus the text with that phrase removed. Default (nil) means
    /// "use now" — handled by the caller.
    private static func extractDate(from text: String, now: Date) -> (Date?, String) {
        let cal = Calendar.current
        let lower = text.lowercased()

        func without(_ phrase: String) -> String {
            guard let r = text.range(of: phrase, options: .caseInsensitive) else { return text }
            var s = text; s.removeSubrange(r); return s
        }

        if let m = firstMatch("(\\d{1,2})\\s+days?\\s+ago", in: text) {
            let ns = text as NSString
            let chunk = ns.substring(with: m)
            if let dm = firstMatch("\\d{1,2}", in: chunk),
               let n = Int((chunk as NSString).substring(with: dm)) {
                var s = text; s.removeSubrange(Range(m, in: text)!)
                return (cal.date(byAdding: .day, value: -n, to: now), s)
            }
        }
        if lower.contains("yesterday") {
            return (cal.date(byAdding: .day, value: -1, to: now), without("yesterday"))
        }
        if lower.contains("last week") {
            return (cal.date(byAdding: .day, value: -7, to: now), without("last week"))
        }
        if lower.contains("today") {
            return (now, without("today"))
        }
        return (nil, text)
    }

    // MARK: - Amount

    private struct Hit { let value: Decimal; let range: Range<String.Index> }

    private static func amount(in text: String) -> Hit? {
        let ns = text as NSString
        // Currency-tagged first: €/$/£ next to a number, either side.
        let tagged = "(?:[€$£]\\s?\\d+(?:[.,]\\d{1,2})?)|(?:\\d+(?:[.,]\\d{1,2})?\\s?[€$£])"
        if let m = firstMatch(tagged, in: text), let v = decimal(ns.substring(with: m)) {
            return Hit(value: v, range: Range(m, in: text)!)
        }
        // Otherwise: every bare number; the largest is the amount.
        let numbers = matches("\\d+(?:[.,]\\d{1,2})?", in: text)
        let valued = numbers.compactMap { r -> (Decimal, NSRange)? in
            decimal(ns.substring(with: r)).map { ($0, r) }
        }
        guard let best = valued.max(by: { $0.0 < $1.0 }) else { return nil }
        return Hit(value: best.0, range: Range(best.1, in: text)!)
    }

    // MARK: - Quantity

    private struct QtyHit { let value: Int; let range: Range<String.Index> }

    private static func leadingQuantity(in text: String, excluding amount: Hit) -> QtyHit? {
        // "2 coffees", "2x coffees", "2 × coffees" — a 1–2 digit integer at
        // the very start, followed by a word. Lookahead so the match
        // covers only the "2 " part, not the word's first letter.
        guard let m = firstMatch("^\\s*(\\d{1,2})\\s*[x×]?\\s+(?=[A-Za-z])", in: text) else { return nil }
        let ns = text as NSString
        // Pull just the digits out of the match.
        guard let digits = firstMatch("\\d{1,2}", in: ns.substring(with: m)) else { return nil }
        let full = Range(m, in: text)!
        let digitStr = (ns.substring(with: m) as NSString).substring(with: digits)
        guard let q = Int(digitStr), q > 1 else { return nil }
        // Don't treat the amount's own number as a quantity.
        if Decimal(q) == amount.value, text.distance(from: text.startIndex, to: full.lowerBound) ==
            text.distance(from: text.startIndex, to: amount.range.lowerBound) { return nil }
        return QtyHit(value: q, range: full)
    }

    // MARK: - Payee

    private static func cleanPayee(_ text: String,
                                   amountRange: Range<String.Index>,
                                   quantityRange: Range<String.Index>?) -> String {
        var out = ""
        for idx in text.indices where idx >= text.startIndex {
            if amountRange.contains(idx) { continue }
            if let q = quantityRange, q.contains(idx) { continue }
            out.append(text[idx])
        }
        // Drop currency symbols and filler words.
        out = out.replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "")
        let fillers: Set<String> = ["for", "x", "×", "at", "@", "-", "—"]
        let words = out
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { !fillers.contains($0.lowercased()) }
        let joined = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard let first = joined.first else { return "" }
        return first.uppercased() + joined.dropFirst()
    }

    // MARK: - Regex helpers

    private static func firstMatch(_ pattern: String, in text: String) -> NSRange? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let r = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.range
        return (r?.location == NSNotFound) ? nil : r
    }

    private static func matches(_ pattern: String, in text: String) -> [NSRange] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
    }

    private static func decimal(_ s: String) -> Decimal? {
        let cleaned = s.filter { "0123456789.,".contains($0) }
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned)
    }
}
