import Foundation

/// Classifies merchants by their *behavioural* role rather than their
/// taxonomic category, so the analytics screen can surface non-obvious
/// patterns: "you've spent X on fast food this month", "your sober streak
/// is Y days", "Z% of your shopping was at premium retailers".
///
/// Match rules are payee-substring based — case-insensitive, anchored
/// loosely so "Tesco" matches both "Tesco Express Camden" and
/// "TESCO EXTRA LIFFEY VALLEY". The catalogue is intentionally Ireland-
/// leaning (matches what the demo seeder uses); add a region-aware
/// variant if/when we go beyond IE/UK.
///
/// One transaction can be in multiple buckets — e.g. a Marks & Spencer
/// food shop is both `groceries` (already covered by `TxCategory`) and
/// `premiumRetail`. The buckets we expose here are the behavioural
/// overlays the AnalyticsMetrics module consumes; they don't replace
/// categories.
enum MerchantClassifier {

    enum Bucket: String, CaseIterable {
        case fastFood
        case coffee
        case alcohol
        case premiumRetail
        case valueRetail
    }

    /// Returns every bucket the merchant belongs to. Most return at most
    /// one or none — the multi-membership case is rare (M&S = grocery +
    /// premium).
    static func buckets(forPayee payee: String,
                        categoryName: String? = nil) -> Set<Bucket> {
        let p = payee.lowercased()
        var out: Set<Bucket> = []

        if matches(p, anyOf: fastFoodPatterns) {
            out.insert(.fastFood)
        }
        if matches(p, anyOf: coffeePatterns) {
            out.insert(.coffee)
        }
        // Alcohol bucket: prefer category match (most reliable signal),
        // fall back to known off-licence / pub merchant names.
        if categoryName?.lowercased() == "alcohol"
            || matches(p, anyOf: alcoholPatterns) {
            out.insert(.alcohol)
        }
        if matches(p, anyOf: premiumPatterns) {
            out.insert(.premiumRetail)
        }
        if matches(p, anyOf: valuePatterns) {
            out.insert(.valueRetail)
        }
        return out
    }

    static func isFastFood(_ payee: String) -> Bool {
        matches(payee.lowercased(), anyOf: fastFoodPatterns)
    }
    static func isCoffee(_ payee: String) -> Bool {
        matches(payee.lowercased(), anyOf: coffeePatterns)
    }
    static func isAlcohol(payee: String, categoryName: String? = nil) -> Bool {
        categoryName?.lowercased() == "alcohol"
            || matches(payee.lowercased(), anyOf: alcoholPatterns)
    }
    static func isPremiumRetail(_ payee: String) -> Bool {
        matches(payee.lowercased(), anyOf: premiumPatterns)
    }
    static func isValueRetail(_ payee: String) -> Bool {
        matches(payee.lowercased(), anyOf: valuePatterns)
    }

    // MARK: - Patterns
    //
    // All entries lowercased, treated as substrings. Order doesn't
    // matter — we check membership. Be careful about ambiguous
    // substrings ("starbucks coffee" needs no separate "coffee" entry).

    /// Quick service / delivery / late-night. Excludes sit-down
    /// restaurants ("Bunsen", "Manifesto" are dining-out, not fast food).
    private static let fastFoodPatterns: [String] = [
        // Pizza chains
        "domino's", "dominos", "apache pizza", "four star pizza",
        "pizza hut", "papa john",
        // Burger / chicken chains
        "mcdonald", "burger king", "kfc", "five guys",
        "wendy", "supermac", "eddie rocket",
        // Other quick service
        "subway", "boojum", "chopped", "freshly chopped",
        "leon", "spar deli", "centra deli",
        // Delivery aggregators (mark order itself as fast food)
        "just eat", "deliveroo", "uber eats"
    ]

    /// Cafés + chain coffee. Match on common chain names and the words
    /// "café"/"cafe"/"coffee" — but not "ice coffee" type false positives
    /// (we substring on payee, not random text).
    private static let coffeePatterns: [String] = [
        "starbucks", "costa", "insomnia", "java republic",
        "butlers café", "butlers cafe", "butlers chocolate",
        "3fe", "black & stone", "two pups", "cinnamon",
        "cafe nero", "caffè nero", "kaffeine",
        // Generic café/coffee suffix — fairly safe because most non-coffee
        // merchants don't end with these.
        " café", " cafe", " coffee", "coffeebar", "espresso bar"
    ]

    /// Off-licences and pubs. Most alcohol is matched via the "Alcohol"
    /// category — these are belt-and-braces.
    private static let alcoholPatterns: [String] = [
        "off licence", "off license", "off-licence", "off-license",
        "the long hall", "hairy lemon", "fibber",
        "p.mac", "mulligan", "mcgowans", "kehoe", "lillie's bordello",
        "molloy's liquor", "o'briens wine", "obriens wine",
        "eight degrees", "guinness storehouse", "kennedy's bar",
        // Generic pub words — careful, "the bar" alone is ambiguous so we
        // require the apostrophe-s form or "tavern"/"taproom".
        "tavern", "taproom", "brewing", "brewpub", "ale house"
    ]

    /// Premium retailers — where the same item would typically cost
    /// noticeably less at a value chain. Used by the "Brand Tax" insight.
    private static let premiumPatterns: [String] = [
        "brown thomas", "marks & spencer", "m&s", "marks and spencer",
        "avoca", "donnybrook fair", "fallon & byrne",
        "tesco finest",                              // own-brand premium tier
        "harvey nichols", "selfridges", "arnotts",
        "supervalu signature", "dunnes simply better"
    ]

    /// Value retailers — discount chains and own-brand-heavy supermarkets.
    private static let valuePatterns: [String] = [
        "aldi", "lidl", "penneys", "primark",
        "tk maxx", "tkmaxx", "homestore + more", "homestore and more",
        "iceland", "dealz", "euro 2", "mr price",
        "b&m", "b & m"
    ]

    // MARK: - Helpers

    private static func matches(_ haystack: String, anyOf patterns: [String]) -> Bool {
        patterns.contains { haystack.contains($0) }
    }
}
