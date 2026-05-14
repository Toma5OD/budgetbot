import Foundation

/// Collapses "TESCO DUBLIN 04 *MOBILE", "Tesco", "tesco" all to the same
/// match key so they don't show up as three distinct merchants in analytics.
/// Two pieces:
///
/// - `key(_:)` is the case-insensitive, suffix-stripped, alphanumerics-only
///   form used purely for comparison. Never shown.
/// - `canonical(forKey:in:fallback:)` finds an existing transaction with the
///   same key and returns whatever spelling the user already accepted, so
///   commits inherit the canonical form.
enum PayeeNormaliser {

    /// Suffixes / artefacts that creep into card statement payee strings and
    /// don't belong in the human-readable name. Stripped before normalising.
    private static let trailingJunkPatterns: [String] = [
        // Run-of-digits tail: strips " 04 12345" and " 04". Bites
        // before the corporate-suffix one so we don't strip "Ltd 04" backwards.
        #"(\s+\d+)+$"#,
        // " *MONTHLY", " *123", " *MOBILE"
        #"\s+\*[A-Z0-9]+$"#,
        // " #1234"
        #"\s+#[0-9]+$"#,
        // " Limited", " Ltd.", " Inc."
        #"\s+(?:LIMITED|LTD\.?|LLC|GMBH|SARL|PLC|INC\.?|CO\.?)$"#
    ]

    /// Case-insensitive alphanumeric match key. Stable across small
    /// formatting differences ("Chemist Warehouse", "CHEMIST WAREHOUSE",
    /// "Chemist Warehouse Ltd.", "chemist-warehouse").
    static func key(_ raw: String) -> String {
        var stripped = raw
        for pattern in trailingJunkPatterns {
            stripped = stripped.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return stripped.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
    }

    /// Canonical user-visible spelling: returns the most recently committed
    /// transaction's payee for this key, or the fallback.
    static func canonical(forKey key: String, in existing: [String], fallback: String) -> String {
        if let match = existing.first(where: { Self.key($0) == key }) {
            return match
        }
        return fallback
    }
}
