import Foundation

/// Best-effort default category for a *merchant*, used only where there's
/// no item detail to go on — an un-itemised bank charge ("Tesco €50") or
/// a quick-added line. Per-item categorisation (the duck-vs-rice problem)
/// needs a receipt; a bare bank line has only the merchant, so the
/// merchant is the honest best signal here.
///
/// Returns a default-catalogue category name, or nil when nothing
/// recognisable matches (caller leaves it uncategorised).
enum MerchantCategory {

    static func resolve(_ payee: String) -> String? {
        let p = payee.lowercased()
        return map.first { $0.patterns.contains { p.contains($0) } }?.category
    }

    private struct Entry { let patterns: [String]; let category: String }

    // Order matters: first match wins, so put specific patterns before
    // generic ones. Ireland-leaning, mirrors BrandCatalog + the demo.
    private static let map: [Entry] = [
        Entry(patterns: ["tesco", "lidl", "aldi", "supervalu", "dunnes", "centra",
                         "spar", "daybreak", "iceland", "grocer", "supermarket"],
              category: "Groceries"),
        Entry(patterns: ["starbucks", "costa", "insomnia", "caffè nero", "cafe nero",
                         "java republic", "butlers", "3fe", "two pups"],
              category: "Coffee"),
        Entry(patterns: ["mcdonald", "burger king", "kfc", "subway", "supermac",
                         "domino", "apache pizza", "boojum", "five guys",
                         "eddie rocket", "just eat", "deliveroo", "uber eats"],
              category: "Dining"),
        Entry(patterns: ["circle k", "circlek", "maxol", "applegreen", "texaco",
                         "esso", "petrol", "diesel"],
              category: "Fuel"),
        Entry(patterns: ["leap card", "dublin bus", "irish rail", "iarnród", "luas",
                         "bus éireann", "bus eireann"],
              category: "Public Transport"),
        Entry(patterns: ["free now", "lynk", "uber", " taxi", "cab co"],
              category: "Taxi & Ride-share"),
        Entry(patterns: ["boots", "hickeys", "pharmacy", "chemist"],
              category: "Pharmacy"),
        Entry(patterns: ["specsavers", "dental", "dentist", "doctor", "clinic", "hospital"],
              category: "Medical"),
        Entry(patterns: ["electric ireland", "energia", "airtricity", "pinergy",
                         "prepaypower", "esb"],
              category: "Electricity"),
        Entry(patterns: ["bord gáis", "bord gais", "calor", "flogas"],
              category: "Heating & Gas"),
        Entry(patterns: ["irish water", "uisce"],
              category: "Water"),
        Entry(patterns: ["vodafone", "gomo", "three mobile", "three ireland",
                         "tesco mobile", "eir mobile", "48.ie"],
              category: "Mobile Plan"),
        Entry(patterns: ["virgin media", "eir broadband", "sky broadband", "broadband"],
              category: "Internet"),
        Entry(patterns: ["netflix", "spotify", "disney", "prime video", "apple tv",
                         "paramount", "now tv", "youtube premium", "crunchyroll", "audible"],
              category: "Streaming"),
        Entry(patterns: ["aer lingus", "ryanair", "airbnb", "booking.com", "hotel", "hostel"],
              category: "Travel"),
        Entry(patterns: ["amazon", "ebay", "currys", "harvey norman", "argos", "smyths"],
              category: "Shopping"),
        Entry(patterns: ["penneys", "primark", "zara", "h&m", "tk maxx", "brown thomas",
                         "asos", "decathlon"],
              category: "Clothing"),
        Entry(patterns: ["off licence", "off-licence", "off license", "molloy",
                         "o'briens wine", "obriens wine"],
              category: "Alcohol"),
        Entry(patterns: ["flyefit", "gym", "anytime fitness", "puregym"],
              category: "Other Subscriptions"),
        Entry(patterns: ["aib", "bank of ireland", "revolut atm", "atm"],
              category: "Cash Withdrawal")
    ]
}
