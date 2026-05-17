import Foundation

/// One known brand. Pure metadata — no image bytes.
///
///   - `matchKeys`  lowercased substrings; if a subscription's display
///     name contains one, this brand matches.
///   - `domain`     the brand's web domain. The real logo is fetched
///     by domain from the logo API and cached — see `BrandLogoStore`.
struct Brand: Identifiable, Hashable {
    let id: String
    let matchKeys: [String]
    let displayName: String
    let domain: String
}

/// Subscription-name → brand lookup. Every entry carries a `domain`;
/// the real full-colour logo is fetched from it once and cached, so
/// there's nothing to bundle and no script to run.
enum BrandCatalog {

    static let all: [Brand] = [
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
              displayName: "FlyeFit", domain: "flyefit.ie")
    ]

    /// First brand whose match keys appear in `name`. Longer keys are
    /// tried first so a specific phrase wins over a generic substring.
    static func match(name: String) -> Brand? {
        let n = name.lowercased()
        return all
            .flatMap { brand in brand.matchKeys.map { (brand, $0) } }
            .sorted { $0.1.count > $1.1.count }
            .first { n.contains($0.1) }?
            .0
    }
}
