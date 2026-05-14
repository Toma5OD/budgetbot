import Foundation

/// Maps every category name in the default catalogue to one of three
/// behavioural buckets:
///
///   - `.necessary` — you'd spend on this regardless of mood. Rent, bills,
///     groceries, transport, medical. Useful as the floor for what the user
///     *can't* cut.
///   - `.discretionary` — fun money. Dining, coffee, shopping, hobbies. The
///     stuff most personal-finance advice tells you to look at first.
///   - `.regret` — categories that are almost always indulgences. Currently
///     just alcohol & gambling; everything else only becomes a regret when
///     the user marks an individual transaction in Hall of Shame.
///
/// Unknown / custom categories default to `.discretionary` — it's the safer
/// side to put unknowns in, because labelling something "necessary" without
/// evidence would understate the user's actual flexibility.
///
/// Pure data, no dependencies. The catalogue mirrors `TxCategory.defaults`.
enum CategoryClassifier {

    enum Bucket: String, Codable, CaseIterable, Identifiable {
        case necessary, discretionary, regret
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .necessary:     return "Necessary"
            case .discretionary: return "Discretionary"
            case .regret:        return "Vice"
            }
        }
        var emoji: String {
            switch self {
            case .necessary:     return "🧱"
            case .discretionary: return "🎈"
            case .regret:        return "🍻"
            }
        }
    }

    /// Maps known category names to a bucket. Income categories return nil
    /// (they aren't classified — money in isn't necessary or discretionary).
    static func bucket(forCategoryName name: String?) -> Bucket? {
        guard let raw = name?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return .discretionary       // unknown defaults to discretionary
        }
        let normalised = raw.lowercased()

        if incomeCategories.contains(normalised) { return nil }
        if vice.contains(normalised)             { return .regret }
        if necessary.contains(normalised)        { return .necessary }
        return .discretionary
    }

    // MARK: - Catalogues (lower-cased)

    /// Income categories — not bucketed at all.
    private static let incomeCategories: Set<String> = [
        "salary", "freelance", "investment returns", "refund",
        "gift received", "interest", "other income"
    ]

    /// Things you'd have to spend on even in a tight month. Tilted
    /// conservative — public transport is necessary, taxis are not;
    /// pharmacy is necessary, personal-care isn't.
    private static let necessary: Set<String> = [
        // Housing
        "rent", "mortgage", "electricity", "heating & gas", "water",
        "internet", "mobile plan", "insurance", "taxes", "bank fees",
        "loan payment",
        // Health
        "pharmacy", "medical",
        // Food at home
        "groceries",
        // Transport you can't easily skip
        "fuel", "public transport", "car maintenance",
        // Family
        "childcare", "education",
        // Generic
        "other expense"
    ]

    /// Always-vice categories — alcohol & gambling. Tobacco would go here
    /// if a category existed for it. Note: Hall of Shame regrets are
    /// classified at the *transaction* level, not via this set — a single
    /// "Dining" transaction can be a regret without making the whole
    /// Dining category one.
    private static let vice: Set<String> = [
        "alcohol"
    ]
}
