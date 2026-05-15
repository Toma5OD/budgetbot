import Foundation

/// Built-in "things you could buy" catalogue. Used by
/// `CounterfactualEngine` as the universal fallback when the user
/// hasn't added any custom dreams — so the "What it could've been"
/// Analytics card has something to show day one.
///
/// Prices are rough EUR-2026 reference points for IE/UK. They don't
/// need to be exact — these are conversational anchors ("1 pair of
/// AirPods Pro" / "a weekend in Lisbon"), not financial advice. We
/// keep the catalogue intentionally short so the rotation through
/// counterfactuals stays interesting.
///
/// To add a new entry: append to `all`, pick a stable `id` that won't
/// collide with later additions, and keep `price` in EUR — the
/// counterfactual engine FX-converts at compute time.
struct ReferencePurchase: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let price: Decimal     // EUR
    let kind: Kind

    /// Price bracket — drives which vice pools we pair with which
    /// references. Putting "year of home-brewed coffee" against
    /// "alcohol spend" makes sense; putting "BMW M3" against
    /// "alcohol spend" only makes sense at long enough timescales.
    enum Kind: String, Hashable {
        case lifestyle   // < €1,500 — pair with monthly spend
        case big         // €1,500 – €25,000 — pair with annual or lifetime
        case biggest     // > €25,000 — pair with lifetime
    }

    static let all: [ReferencePurchase] = [
        // Lifestyle
        ReferencePurchase(id: "homebrew-year",
                          name: "A year of home-brewed coffee",
                          emoji: "☕️", price: 150, kind: .lifestyle),
        ReferencePurchase(id: "weekend-lisbon",
                          name: "A weekend in Lisbon",
                          emoji: "✈️", price: 450, kind: .lifestyle),
        ReferencePurchase(id: "airpods-pro",
                          name: "AirPods Pro",
                          emoji: "🎧", price: 279, kind: .lifestyle),
        ReferencePurchase(id: "ps5",
                          name: "A PS5 + a couple of games",
                          emoji: "🎮", price: 620, kind: .lifestyle),
        ReferencePurchase(id: "apple-watch",
                          name: "Apple Watch Series 11",
                          emoji: "⌚️", price: 449, kind: .lifestyle),
        ReferencePurchase(id: "iphone-pro",
                          name: "iPhone 17 Pro",
                          emoji: "📱", price: 1_199, kind: .lifestyle),

        // Big
        ReferencePurchase(id: "european-holiday",
                          name: "Two weeks in Italy with someone",
                          emoji: "🍝", price: 3_500, kind: .big),
        ReferencePurchase(id: "engagement-ring",
                          name: "A decent engagement ring",
                          emoji: "💍", price: 5_000, kind: .big),
        ReferencePurchase(id: "ebike",
                          name: "A proper e-bike",
                          emoji: "🚴", price: 3_200, kind: .big),
        ReferencePurchase(id: "macbook-pro",
                          name: "A new MacBook Pro 14\"",
                          emoji: "💻", price: 2_300, kind: .big),
        ReferencePurchase(id: "secondhand-bmw",
                          name: "A clean second-hand BMW 3 Series",
                          emoji: "🚗", price: 18_000, kind: .big),
        ReferencePurchase(id: "irish-wedding",
                          name: "An Irish wedding (median)",
                          emoji: "🎩", price: 30_000, kind: .biggest),

        // Biggest
        ReferencePurchase(id: "mortgage-deposit-3bed",
                          name: "10% deposit on a €450k 3-bed",
                          emoji: "🏠", price: 45_000, kind: .biggest),
        ReferencePurchase(id: "mortgage-deposit-dublin",
                          name: "10% deposit on a €550k Dublin apt",
                          emoji: "🏙", price: 55_000, kind: .biggest),
        ReferencePurchase(id: "new-bmw-m3",
                          name: "A new BMW M3",
                          emoji: "🏎", price: 95_000, kind: .biggest)
    ]
}
