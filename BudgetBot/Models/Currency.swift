import Foundation

/// Currencies BudgetBot supports first-class. Every code here has a stable FX
/// rate against EUR from the ECB daily feed, so multi-currency aggregation
/// always produces a real number.
///
/// Source list: ECB euro reference rates (≈30 currencies) + EUR itself.
/// See `FXService` for the feed wiring.
struct Currency: Identifiable, Hashable, Codable, Sendable {
    let code: String       // ISO 4217, e.g. "EUR"
    let name: String       // "Euro"
    let symbol: String     // "€"
    var id: String { code }

    var displayLabel: String {
        "\(symbol)  \(code)  ·  \(name)"
    }
}

enum Currencies {
    /// Order: euro first, then the user's likely regional defaults, then
    /// alphabetical for the rest.
    static let supported: [Currency] = [
        Currency(code: "EUR", name: "Euro",                  symbol: "€"),
        Currency(code: "USD", name: "US Dollar",             symbol: "$"),
        Currency(code: "GBP", name: "British Pound",         symbol: "£"),
        Currency(code: "CHF", name: "Swiss Franc",           symbol: "CHF"),
        Currency(code: "JPY", name: "Japanese Yen",          symbol: "¥"),
        Currency(code: "AUD", name: "Australian Dollar",     symbol: "A$"),
        Currency(code: "BGN", name: "Bulgarian Lev",         symbol: "лв"),
        Currency(code: "BRL", name: "Brazilian Real",        symbol: "R$"),
        Currency(code: "CAD", name: "Canadian Dollar",       symbol: "C$"),
        Currency(code: "CNY", name: "Chinese Yuan",          symbol: "¥"),
        Currency(code: "CZK", name: "Czech Koruna",          symbol: "Kč"),
        Currency(code: "DKK", name: "Danish Krone",          symbol: "kr"),
        Currency(code: "HKD", name: "Hong Kong Dollar",      symbol: "HK$"),
        Currency(code: "HUF", name: "Hungarian Forint",      symbol: "Ft"),
        Currency(code: "IDR", name: "Indonesian Rupiah",     symbol: "Rp"),
        Currency(code: "ILS", name: "Israeli Shekel",        symbol: "₪"),
        Currency(code: "INR", name: "Indian Rupee",          symbol: "₹"),
        Currency(code: "ISK", name: "Icelandic Króna",       symbol: "kr"),
        Currency(code: "KRW", name: "South Korean Won",      symbol: "₩"),
        Currency(code: "MXN", name: "Mexican Peso",          symbol: "$"),
        Currency(code: "MYR", name: "Malaysian Ringgit",     symbol: "RM"),
        Currency(code: "NOK", name: "Norwegian Krone",       symbol: "kr"),
        Currency(code: "NZD", name: "New Zealand Dollar",    symbol: "NZ$"),
        Currency(code: "PHP", name: "Philippine Peso",       symbol: "₱"),
        Currency(code: "PLN", name: "Polish Złoty",          symbol: "zł"),
        Currency(code: "RON", name: "Romanian Leu",          symbol: "lei"),
        Currency(code: "SEK", name: "Swedish Krona",         symbol: "kr"),
        Currency(code: "SGD", name: "Singapore Dollar",      symbol: "S$"),
        Currency(code: "THB", name: "Thai Baht",             symbol: "฿"),
        Currency(code: "TRY", name: "Turkish Lira",          symbol: "₺"),
        Currency(code: "ZAR", name: "South African Rand",    symbol: "R")
    ]

    static func by(code: String) -> Currency? {
        let upper = code.uppercased()
        return supported.first { $0.code == upper }
    }

    /// The user's regional currency from `Locale.current`, falling back to EUR.
    /// If the locale's currency isn't in our supported list, also EUR — better
    /// to show a real currency we can convert than a placeholder we can't.
    static var localeDefault: String {
        let raw = Locale.current.currency?.identifier ?? "EUR"
        return by(code: raw)?.code ?? "EUR"
    }
}
