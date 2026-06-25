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

    /// Maps a *category* to a need/want bucket. Need vs want is a property
    /// of what was bought, so this only answers when there's a category to
    /// go on (ideally a per-item one on a split). It never guesses from the
    /// merchant — a Tesco basket holds both rice and an inflatable duck.
    ///
    /// Returns nil when we can't honestly classify — income, or no/unknown
    /// category. The caller (need-vs-want) **excludes** nil rather than
    /// dumping it into "want", so the split reflects only what's actually
    /// known, not everything you haven't itemised yet.
    static func bucket(forCategoryName name: String?) -> Bucket? {
        guard let raw = name?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil       // uncategorised → not counted (don't guess)
        }
        let normalised = raw.lowercased()

        if incomeCategories.contains(normalised) { return nil }
        if vice.contains(normalised)             { return .regret }
        if necessary.contains(normalised)        { return .necessary }
        if discretionary.contains(normalised)    { return .discretionary }
        return nil           // unknown / custom category → not counted
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
        "childcare", "education"
    ]

    /// Known discretionary ("want") categories. Kept explicit so that an
    /// *unknown* or custom category falls through to "not counted" rather
    /// than being silently treated as a want.
    private static let discretionary: Set<String> = [
        "dining", "coffee", "taxi & ride-share", "parking",
        "streaming", "other subscriptions", "personal care",
        "home & garden", "pets", "entertainment", "shopping",
        "clothing", "electronics", "books & media", "hobbies",
        "travel", "charity", "gifts given"
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
