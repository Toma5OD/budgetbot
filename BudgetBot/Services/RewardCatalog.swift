import Foundation

/// One finish-line reward a user can attach to a savings goal.
///
/// Reward delivery is the business deal we haven't signed yet — for now
/// the app stores the *choice*, displays it as the carrot during the
/// grind, and shows a "claim" stub when the goal hits. Wiring this to a
/// real gifting partner is a future change at the `claim` action only.
struct RewardPackage: Identifiable, Hashable {
    enum Tier: String, Hashable {
        case small, medium, large
    }

    let id: String
    let displayName: String
    /// One-line description shown in the picker and on the goal card.
    let description: String
    let sfSymbol: String
    /// Indicative price range — what the user would pay the partner on
    /// claim, not what BudgetBot charges. Strings, not numbers, because
    /// these get displayed verbatim.
    let priceRange: String
    /// Sized to the goal so the celebration matches the win.
    let tier: Tier
    /// Surfaces a "contains alcohol" tag — sober users can pick around it.
    let containsAlcohol: Bool
}

/// The reward packages on offer. Curated, intentionally small — every
/// tier covered, mix of alcohol and not, no overlap. Edit this list to
/// add or rebalance offerings.
enum RewardCatalog {

    static let all: [RewardPackage] = [
        // ── Small (~< €500 goals) ───────────────────────────────
        RewardPackage(id: "treat_box",
                      displayName: "Treat Box",
                      description: "Artisan chocolates plus a handwritten card.",
                      sfSymbol: "shippingbox.fill",
                      priceRange: "€25–45",
                      tier: .small,
                      containsAlcohol: false),
        RewardPackage(id: "coffee_month",
                      displayName: "Coffee On Us",
                      description: "Voucher for a month of takeaway coffees at your local.",
                      sfSymbol: "cup.and.saucer.fill",
                      priceRange: "€40",
                      tier: .small,
                      containsAlcohol: false),
        RewardPackage(id: "flowers_chocolates",
                      displayName: "Flowers & Chocolates",
                      description: "Hand-tied seasonal bouquet with a chocolate box.",
                      sfSymbol: "leaf.fill",
                      priceRange: "€45–70",
                      tier: .small,
                      containsAlcohol: false),

        // ── Medium (€500–€10k goals) ────────────────────────────
        RewardPackage(id: "champagne_night",
                      displayName: "Champagne Night",
                      description: "Bottle of champagne, premium chocolates and flowers.",
                      sfSymbol: "wineglass.fill",
                      priceRange: "€90–140",
                      tier: .medium,
                      containsAlcohol: true),
        RewardPackage(id: "dinner_two",
                      displayName: "Dinner For Two",
                      description: "Restaurant gift card good for a proper night out.",
                      sfSymbol: "fork.knife",
                      priceRange: "€100–160",
                      tier: .medium,
                      containsAlcohol: false),
        RewardPackage(id: "spa_day",
                      displayName: "Spa Day",
                      description: "Full-day pass with treatments at a partner spa.",
                      sfSymbol: "sparkles",
                      priceRange: "€120–180",
                      tier: .medium,
                      containsAlcohol: false),

        // ── Large (€10k+ goals) ─────────────────────────────────
        RewardPackage(id: "weekend_away",
                      displayName: "Weekend Away",
                      description: "Two-night stay at a partner hotel, breakfast included.",
                      sfSymbol: "bed.double.fill",
                      priceRange: "€350–600",
                      tier: .large,
                      containsAlcohol: false),
        RewardPackage(id: "big_bash",
                      displayName: "The Big Bash",
                      description: "Premium champagne, tasting-menu dinner for two, flowers.",
                      sfSymbol: "party.popper.fill",
                      priceRange: "€250–400",
                      tier: .large,
                      containsAlcohol: true)
    ]

    static func get(id: String) -> RewardPackage? {
        all.first { $0.id == id }
    }

    /// Sizes a reward to the goal. Anything over €10k is large; anything
    /// under €500 is small; in between is medium.
    static func tier(forGoalAmount amount: Decimal) -> RewardPackage.Tier {
        if amount >= 10_000 { return .large }
        if amount >= 500    { return .medium }
        return .small
    }
}
