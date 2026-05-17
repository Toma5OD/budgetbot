import Foundation

/// One known brand. Pure metadata — no image bytes.
///
///   - `matchKeys`  lowercased substrings; if a payee or subscription
///     name contains one, this brand matches.
///   - `domain`     the brand's web domain. The real logo is fetched
///     by domain from the favicon service and cached — see
///     `BrandLogoStore`.
struct Brand: Identifiable, Hashable {
    let id: String
    let matchKeys: [String]
    let displayName: String
    let domain: String
}

/// Brand lookup for subscriptions *and* everyday merchants. Every entry
/// carries a `domain`; the real full-colour logo is fetched from it once
/// and cached, so there's nothing to bundle and no script to run.
///
/// Match keys are deliberately Ireland-leaning (they track what the demo
/// seeder and most users here actually spend on) — add a region-aware
/// variant if/when the app goes beyond IE/UK.
enum BrandCatalog {

    static let all: [Brand] = [
        // ══ Subscriptions ════════════════════════════════════════
        // ── Streaming video ──────────────────────────────────────
        Brand(id: "netflix",       matchKeys: ["netflix"],
              displayName: "Netflix", domain: "netflix.com"),
        Brand(id: "disneyplus",    matchKeys: ["disney"],
              displayName: "Disney+", domain: "disneyplus.com"),
        Brand(id: "primevideo",    matchKeys: ["prime video", "amazon prime"],
              displayName: "Prime Video", domain: "primevideo.com"),
        Brand(id: "appletv",       matchKeys: ["apple tv"],
              displayName: "Apple TV+", domain: "tv.apple.com"),
        Brand(id: "paramountplus", matchKeys: ["paramount"],
              displayName: "Paramount+", domain: "paramountplus.com"),
        Brand(id: "hulu",          matchKeys: ["hulu"],
              displayName: "Hulu", domain: "hulu.com"),
        Brand(id: "max",           matchKeys: ["hbo"],
              displayName: "Max", domain: "max.com"),
        Brand(id: "crunchyroll",   matchKeys: ["crunchyroll"],
              displayName: "Crunchyroll", domain: "crunchyroll.com"),
        Brand(id: "twitch",        matchKeys: ["twitch"],
              displayName: "Twitch", domain: "twitch.tv"),

        // ── Music / audio ────────────────────────────────────────
        Brand(id: "spotify",       matchKeys: ["spotify"],
              displayName: "Spotify", domain: "spotify.com"),
        Brand(id: "applemusic",    matchKeys: ["apple music"],
              displayName: "Apple Music", domain: "music.apple.com"),
        Brand(id: "youtubemusic",  matchKeys: ["youtube music"],
              displayName: "YouTube Music", domain: "music.youtube.com"),
        Brand(id: "tidal",         matchKeys: ["tidal"],
              displayName: "Tidal", domain: "tidal.com"),
        Brand(id: "soundcloud",    matchKeys: ["soundcloud"],
              displayName: "SoundCloud", domain: "soundcloud.com"),
        Brand(id: "audible",       matchKeys: ["audible"],
              displayName: "Audible", domain: "audible.com"),

        // ── Video / creators ─────────────────────────────────────
        Brand(id: "youtube",       matchKeys: ["youtube"],
              displayName: "YouTube Premium", domain: "youtube.com"),
        Brand(id: "patreon",       matchKeys: ["patreon"],
              displayName: "Patreon", domain: "patreon.com"),

        // ── Cloud / storage ──────────────────────────────────────
        Brand(id: "icloud",        matchKeys: ["icloud"],
              displayName: "iCloud+", domain: "icloud.com"),
        Brand(id: "dropbox",       matchKeys: ["dropbox"],
              displayName: "Dropbox", domain: "dropbox.com"),
        Brand(id: "googledrive",   matchKeys: ["google one", "google drive"],
              displayName: "Google One", domain: "one.google.com"),

        // ── Productivity / SaaS ──────────────────────────────────
        Brand(id: "notion",        matchKeys: ["notion"],
              displayName: "Notion", domain: "notion.so"),
        Brand(id: "github",        matchKeys: ["github"],
              displayName: "GitHub", domain: "github.com"),
        Brand(id: "openai",        matchKeys: ["chatgpt", "openai"],
              displayName: "ChatGPT", domain: "openai.com"),
        Brand(id: "adobe",         matchKeys: ["adobe"],
              displayName: "Adobe", domain: "adobe.com"),
        Brand(id: "canva",         matchKeys: ["canva"],
              displayName: "Canva", domain: "canva.com"),
        Brand(id: "linkedin",      matchKeys: ["linkedin"],
              displayName: "LinkedIn", domain: "linkedin.com"),

        // ── Gaming ───────────────────────────────────────────────
        Brand(id: "playstation",   matchKeys: ["playstation", "ps plus"],
              displayName: "PlayStation Plus", domain: "playstation.com"),
        Brand(id: "xbox",          matchKeys: ["xbox", "game pass"],
              displayName: "Xbox Game Pass", domain: "xbox.com"),
        Brand(id: "nintendo",      matchKeys: ["nintendo"],
              displayName: "Nintendo Switch Online", domain: "nintendo.com"),

        // ── Learning / lifestyle ─────────────────────────────────
        Brand(id: "duolingo",      matchKeys: ["duolingo"],
              displayName: "Duolingo", domain: "duolingo.com"),
        Brand(id: "nordvpn",       matchKeys: ["nordvpn", "nord vpn"],
              displayName: "NordVPN", domain: "nordvpn.com"),
        Brand(id: "strava",        matchKeys: ["strava"],
              displayName: "Strava", domain: "strava.com"),

        // ── Telecom ──────────────────────────────────────────────
        Brand(id: "vodafone",      matchKeys: ["vodafone"],
              displayName: "Vodafone", domain: "vodafone.ie"),
        Brand(id: "three",         matchKeys: ["three mobile", "three ireland"],
              displayName: "Three", domain: "three.ie"),
        Brand(id: "gomo",          matchKeys: ["gomo"],
              displayName: "GoMo", domain: "gomo.ie"),
        Brand(id: "eir",           matchKeys: ["eir"],
              displayName: "Eir", domain: "eir.ie"),
        Brand(id: "sky",           matchKeys: ["sky "],
              displayName: "Sky", domain: "sky.com"),
        Brand(id: "virginmedia",   matchKeys: ["virgin media"],
              displayName: "Virgin Media", domain: "virginmedia.ie"),

        // ── Utilities ────────────────────────────────────────────
        Brand(id: "electricireland", matchKeys: ["electric ireland"],
              displayName: "Electric Ireland", domain: "electricireland.ie"),
        Brand(id: "bordgais",      matchKeys: ["bord gáis", "bord gais"],
              displayName: "Bord Gáis Energy", domain: "bordgaisenergy.ie"),

        // ── Fitness ──────────────────────────────────────────────
        Brand(id: "flyefit",       matchKeys: ["flyefit"],
              displayName: "FlyeFit", domain: "flyefit.ie"),

        // ══ Everyday merchants ═══════════════════════════════════
        // ── Groceries / supermarkets ─────────────────────────────
        Brand(id: "tesco",        matchKeys: ["tesco"],
              displayName: "Tesco", domain: "tesco.ie"),
        Brand(id: "supervalu",    matchKeys: ["supervalu"],
              displayName: "SuperValu", domain: "supervalu.ie"),
        Brand(id: "dunnesstores", matchKeys: ["dunnes"],
              displayName: "Dunnes Stores", domain: "dunnesstores.com"),
        Brand(id: "lidl",         matchKeys: ["lidl"],
              displayName: "Lidl", domain: "lidl.ie"),
        Brand(id: "aldi",         matchKeys: ["aldi"],
              displayName: "Aldi", domain: "aldi.ie"),
        Brand(id: "centra",       matchKeys: ["centra"],
              displayName: "Centra", domain: "centra.ie"),
        Brand(id: "spar",         matchKeys: ["spar"],
              displayName: "Spar", domain: "spar.ie"),
        Brand(id: "daybreak",     matchKeys: ["daybreak"],
              displayName: "Daybreak", domain: "daybreak.ie"),
        Brand(id: "marksspencer", matchKeys: ["marks & spencer", "marks and spencer", "m&s"],
              displayName: "Marks & Spencer", domain: "marksandspencer.com"),

        // ── Fuel / forecourt ─────────────────────────────────────
        Brand(id: "circlek",      matchKeys: ["circle k", "circlek"],
              displayName: "Circle K", domain: "circlek.ie"),
        Brand(id: "maxol",        matchKeys: ["maxol"],
              displayName: "Maxol", domain: "maxol.ie"),
        Brand(id: "applegreen",   matchKeys: ["applegreen"],
              displayName: "Applegreen", domain: "applegreen.com"),

        // ── Pharmacy / health ────────────────────────────────────
        Brand(id: "boots",        matchKeys: ["boots"],
              displayName: "Boots", domain: "boots.ie"),
        Brand(id: "specsavers",   matchKeys: ["specsavers"],
              displayName: "Specsavers", domain: "specsavers.ie"),

        // ── Fast food / delivery ─────────────────────────────────
        Brand(id: "mcdonalds",    matchKeys: ["mcdonald"],
              displayName: "McDonald's", domain: "mcdonalds.com"),
        Brand(id: "burgerking",   matchKeys: ["burger king"],
              displayName: "Burger King", domain: "burgerking.com"),
        Brand(id: "kfc",          matchKeys: ["kfc"],
              displayName: "KFC", domain: "kfc.ie"),
        Brand(id: "subway",       matchKeys: ["subway"],
              displayName: "Subway", domain: "subway.com"),
        Brand(id: "supermacs",    matchKeys: ["supermac"],
              displayName: "Supermac's", domain: "supermacs.ie"),
        Brand(id: "dominos",      matchKeys: ["domino"],
              displayName: "Domino's", domain: "dominos.ie"),
        Brand(id: "apachepizza",  matchKeys: ["apache pizza"],
              displayName: "Apache Pizza", domain: "apache.ie"),
        Brand(id: "boojum",       matchKeys: ["boojum"],
              displayName: "Boojum", domain: "boojummex.com"),
        Brand(id: "fiveguys",     matchKeys: ["five guys"],
              displayName: "Five Guys", domain: "fiveguys.com"),
        Brand(id: "eddierockets", matchKeys: ["eddie rocket"],
              displayName: "Eddie Rocket's", domain: "eddierockets.ie"),
        Brand(id: "justeat",      matchKeys: ["just eat"],
              displayName: "Just Eat", domain: "just-eat.ie"),
        Brand(id: "deliveroo",    matchKeys: ["deliveroo"],
              displayName: "Deliveroo", domain: "deliveroo.ie"),

        // ── Coffee ───────────────────────────────────────────────
        Brand(id: "starbucks",    matchKeys: ["starbucks"],
              displayName: "Starbucks", domain: "starbucks.com"),
        Brand(id: "costa",        matchKeys: ["costa"],
              displayName: "Costa Coffee", domain: "costa.co.uk"),
        Brand(id: "insomnia",     matchKeys: ["insomnia"],
              displayName: "Insomnia", domain: "insomnia.ie"),
        Brand(id: "butlers",      matchKeys: ["butlers"],
              displayName: "Butlers", domain: "butlerschocolates.com"),
        Brand(id: "javarepublic", matchKeys: ["java republic"],
              displayName: "Java Republic", domain: "javarepublic.com"),

        // ── Retail / department / electronics ────────────────────
        Brand(id: "penneys",      matchKeys: ["penneys", "primark"],
              displayName: "Penneys", domain: "primark.com"),
        Brand(id: "brownthomas",  matchKeys: ["brown thomas"],
              displayName: "Brown Thomas", domain: "brownthomas.com"),
        Brand(id: "arnotts",      matchKeys: ["arnotts"],
              displayName: "Arnotts", domain: "arnotts.ie"),
        Brand(id: "currys",       matchKeys: ["currys"],
              displayName: "Currys", domain: "currys.ie"),
        Brand(id: "harveynorman", matchKeys: ["harvey norman"],
              displayName: "Harvey Norman", domain: "harveynorman.ie"),
        Brand(id: "argos",        matchKeys: ["argos"],
              displayName: "Argos", domain: "argos.ie"),
        Brand(id: "smyths",       matchKeys: ["smyths"],
              displayName: "Smyths Toys", domain: "smythstoys.com"),
        Brand(id: "ikea",         matchKeys: ["ikea"],
              displayName: "IKEA", domain: "ikea.com"),
        Brand(id: "bandq",        matchKeys: ["b&q", "b & q"],
              displayName: "B&Q", domain: "diy.com"),
        Brand(id: "woodies",      matchKeys: ["woodie"],
              displayName: "Woodie's", domain: "woodies.ie"),
        Brand(id: "easons",       matchKeys: ["eason"],
              displayName: "Easons", domain: "easons.com"),
        Brand(id: "tkmaxx",       matchKeys: ["tk maxx", "tkmaxx"],
              displayName: "TK Maxx", domain: "tkmaxx.com"),
        Brand(id: "hm",           matchKeys: ["h&m"],
              displayName: "H&M", domain: "hm.com"),
        Brand(id: "zara",         matchKeys: ["zara"],
              displayName: "Zara", domain: "zara.com"),
        Brand(id: "asos",         matchKeys: ["asos"],
              displayName: "ASOS", domain: "asos.com"),
        Brand(id: "decathlon",    matchKeys: ["decathlon"],
              displayName: "Decathlon", domain: "decathlon.ie"),

        // ── Transport / travel ───────────────────────────────────
        Brand(id: "aerlingus",    matchKeys: ["aer lingus"],
              displayName: "Aer Lingus", domain: "aerlingus.com"),
        Brand(id: "ryanair",      matchKeys: ["ryanair"],
              displayName: "Ryanair", domain: "ryanair.com"),
        Brand(id: "freenow",      matchKeys: ["free now"],
              displayName: "Free Now", domain: "free-now.com"),
        Brand(id: "leapcard",     matchKeys: ["leap card"],
              displayName: "Leap Card", domain: "leapcard.ie"),
        Brand(id: "irishrail",    matchKeys: ["irish rail", "iarnród"],
              displayName: "Irish Rail", domain: "irishrail.ie"),
        Brand(id: "dublinbus",    matchKeys: ["dublin bus"],
              displayName: "Dublin Bus", domain: "dublinbus.ie"),
        Brand(id: "uber",         matchKeys: ["uber"],
              displayName: "Uber", domain: "uber.com"),

        // ── Online / services ────────────────────────────────────
        Brand(id: "amazon",       matchKeys: ["amazon"],
              displayName: "Amazon", domain: "amazon.co.uk"),
        Brand(id: "paypal",       matchKeys: ["paypal"],
              displayName: "PayPal", domain: "paypal.com"),
        Brand(id: "ebay",         matchKeys: ["ebay"],
              displayName: "eBay", domain: "ebay.ie"),
        Brand(id: "eventbrite",   matchKeys: ["eventbrite"],
              displayName: "Eventbrite", domain: "eventbrite.ie"),
        Brand(id: "udemy",        matchKeys: ["udemy"],
              displayName: "Udemy", domain: "udemy.com"),
        Brand(id: "paddypower",   matchKeys: ["paddy power"],
              displayName: "Paddy Power", domain: "paddypower.com"),
        Brand(id: "anpost",       matchKeys: ["an post"],
              displayName: "An Post", domain: "anpost.com"),

        // ── Banking ──────────────────────────────────────────────
        Brand(id: "aib",          matchKeys: ["aib"],
              displayName: "AIB", domain: "aib.ie"),
        Brand(id: "bankofireland", matchKeys: ["bank of ireland"],
              displayName: "Bank of Ireland", domain: "bankofireland.com"),
        Brand(id: "revolut",      matchKeys: ["revolut"],
              displayName: "Revolut", domain: "revolut.com"),

        // ── Charity / drink ──────────────────────────────────────
        Brand(id: "trocaire",     matchKeys: ["trócaire", "trocaire"],
              displayName: "Trócaire", domain: "trocaire.org"),
        Brand(id: "eightdegrees", matchKeys: ["eight degrees"],
              displayName: "Eight Degrees Brewing", domain: "eightdegrees.ie")
    ]

    /// First brand whose match keys appear in `name`. Longer keys are
    /// tried first so a specific phrase ("amazon prime") wins over a
    /// generic substring ("amazon").
    static func match(name: String) -> Brand? {
        let n = name.lowercased()
        return all
            .flatMap { brand in brand.matchKeys.map { (brand, $0) } }
            .sorted { $0.1.count > $1.1.count }
            .first { n.contains($0.1) }?
            .0
    }
}
