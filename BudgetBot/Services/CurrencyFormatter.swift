import Foundation

enum CurrencyFormatter {
    private static var cache: [String: NumberFormatter] = [:]

    static func string(for amount: Decimal, currency: String) -> String {
        let f = formatter(for: currency)
        return f.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    private static func formatter(for currency: String) -> NumberFormatter {
        if let f = cache[currency] { return f }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        cache[currency] = f
        return f
    }
}
