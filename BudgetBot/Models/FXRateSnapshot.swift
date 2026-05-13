import Foundation
import SwiftData

/// Latest ECB daily FX rates expressed as "1 EUR = X target" in a JSON blob
/// so we don't have to migrate the schema each time ECB add a currency.
@Model
final class FXRateSnapshot {
    var id: UUID = UUID()
    var fetchedAt: Date = Date.now
    /// JSON: {"USD": "1.0800", "GBP": "0.8600", ...}. Values are Decimal strings.
    var ratesJSON: String = "{}"

    init(id: UUID = UUID(), fetchedAt: Date = .now, ratesJSON: String = "{}") {
        self.id = id
        self.fetchedAt = fetchedAt
        self.ratesJSON = ratesJSON
    }

    var rates: [String: Decimal] {
        guard let data = ratesJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict.compactMapValues { Decimal(string: $0) }
    }
}
