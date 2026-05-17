import SwiftUI

/// One known brand. Pure metadata — no image bytes live here.
///
///   - `matchKeys`  lowercased substrings; if a subscription's display
///     name contains one, this brand matches.
///   - `assetName`  the asset-catalog name the fetch script writes the
///     bundled (CC0 simple-icons) mark to. May be absent at runtime —
///     `BrandLogoView` checks and falls through.
///   - `tintHex`    the brand's official colour. The bundled marks are
///     monochrome and get tinted with this.
///   - `domain`     used by the remote logo-API tier for brands the
///     bundled set doesn't carry (regional telcos/utilities).
struct Brand: Identifiable, Hashable {
    let id: String
    let matchKeys: [String]
    let displayName: String
    let tintHex: String
    let domain: String?

    /// Name the fetch script writes the bundled mark to (`brand.<id>`).
    var assetName: String { "brand.\(id)" }
    var tint: Color { Color(hex: tintHex) }
}

/// The brand lookup table. Big global subscription brands here get a
/// bundled mark from simple-icons (CC0); Irish regional brands
/// (GoMo, Electric Ireland, …) carry only a `domain` and rely on the
/// logo-API tier — simple-icons doesn't stock them.
///
/// Keep the `id`s in sync with `Scripts/fetch_brand_logos.sh`, which
/// maps each `id` to a simple-icons slug.
enum BrandCatalog {

    static let all: [Brand] = [
        // ── Streaming video ──────────────────────────────────────
        Brand(id: "netflix", matchKeys: ["netflix"], displayName: "Netflix",
              tintHex: "E50914", domain: "netflix.com"),
        Brand(id: "disneyplus", matchKeys: ["disney"], displayName: "Disney+",
              tintHex: "113CCF", domain: "disneyplus.com"),
        Brand(id: "primevideo", matchKeys: ["prime video", "amazon prime"],
              displayName: "Prime Video", tintHex: "1F2E3D", domain: "primevideo.com"),
        Brand(id: "appletv", matchKeys: ["apple tv"], displayName: "Apple TV+",
              tintHex: "000000", domain: "tv.apple.com"),
        Brand(id: "paramountplus", matchKeys: ["paramount"], displayName: "Paramount+",
              tintHex: "0064FF", domain: "paramountplus.com"),
        Brand(id: "hulu", matchKeys: ["hulu"], displayName: "Hulu",
              tintHex: "1CE783", domain: "hulu.com"),
        Brand(id: "max", matchKeys: ["hbo"], displayName: "Max",
              tintHex: "002BE7", domain: "max.com"),
        Brand(id: "crunchyroll", matchKeys: ["crunchyroll"], displayName: "Crunchyroll",
              tintHex: "F47521", domain: "crunchyroll.com"),
        Brand(id: "twitch", matchKeys: ["twitch"], displayName: "Twitch",
              tintHex: "9146FF", domain: "twitch.tv"),

        // ── Music / audio ────────────────────────────────────────
        Brand(id: "spotify", matchKeys: ["spotify"], displayName: "Spotify",
              tintHex: "1DB954", domain: "spotify.com"),
        Brand(id: "applemusic", matchKeys: ["apple music"], displayName: "Apple Music",
              tintHex: "FA2D48", domain: "music.apple.com"),
        Brand(id: "youtubemusic", matchKeys: ["youtube music"], displayName: "YouTube Music",
              tintHex: "FF0000", domain: "music.youtube.com"),
        Brand(id: "tidal", matchKeys: ["tidal"], displayName: "Tidal",
              tintHex: "000000", domain: "tidal.com"),
        Brand(id: "soundcloud", matchKeys: ["soundcloud"], displayName: "SoundCloud",
              tintHex: "FF5500", domain: "soundcloud.com"),
        Brand(id: "audible", matchKeys: ["audible"], displayName: "Audible",
              tintHex: "F8991C", domain: "audible.com"),

        // ── Video / creators ─────────────────────────────────────
        Brand(id: "youtube", matchKeys: ["youtube"], displayName: "YouTube Premium",
              tintHex: "FF0000", domain: "youtube.com"),
        Brand(id: "patreon", matchKeys: ["patreon"], displayName: "Patreon",
              tintHex: "FF424D", domain: "patreon.com"),

        // ── Cloud / storage ──────────────────────────────────────
        Brand(id: "icloud", matchKeys: ["icloud"], displayName: "iCloud+",
              tintHex: "3693F3", domain: "icloud.com"),
        Brand(id: "dropbox", matchKeys: ["dropbox"], displayName: "Dropbox",
              tintHex: "0061FF", domain: "dropbox.com"),
        Brand(id: "googledrive", matchKeys: ["google one", "google drive"],
              displayName: "Google One", tintHex: "4285F4", domain: "one.google.com"),

        // ── Productivity / SaaS ──────────────────────────────────
        Brand(id: "notion", matchKeys: ["notion"], displayName: "Notion",
              tintHex: "000000", domain: "notion.so"),
        Brand(id: "github", matchKeys: ["github"], displayName: "GitHub",
              tintHex: "181717", domain: "github.com"),
        Brand(id: "openai", matchKeys: ["chatgpt", "openai"], displayName: "ChatGPT",
              tintHex: "412991", domain: "openai.com"),
        Brand(id: "adobe", matchKeys: ["adobe"], displayName: "Adobe",
              tintHex: "FF0000", domain: "adobe.com"),
        Brand(id: "canva", matchKeys: ["canva"], displayName: "Canva",
              tintHex: "00C4CC", domain: "canva.com"),
        Brand(id: "linkedin", matchKeys: ["linkedin"], displayName: "LinkedIn",
              tintHex: "0A66C2", domain: "linkedin.com"),

        // ── Gaming ───────────────────────────────────────────────
        Brand(id: "playstation", matchKeys: ["playstation", "ps plus"],
              displayName: "PlayStation Plus", tintHex: "0070D1", domain: "playstation.com"),
        Brand(id: "xbox", matchKeys: ["xbox", "game pass"], displayName: "Xbox Game Pass",
              tintHex: "107C10", domain: "xbox.com"),
        Brand(id: "nintendo", matchKeys: ["nintendo"], displayName: "Nintendo Switch Online",
              tintHex: "E60012", domain: "nintendo.com"),

        // ── Learning / lifestyle ─────────────────────────────────
        Brand(id: "duolingo", matchKeys: ["duolingo"], displayName: "Duolingo",
              tintHex: "58CC02", domain: "duolingo.com"),
        Brand(id: "nordvpn", matchKeys: ["nordvpn", "nord vpn"], displayName: "NordVPN",
              tintHex: "4687FF", domain: "nordvpn.com"),
        Brand(id: "strava", matchKeys: ["strava"], displayName: "Strava",
              tintHex: "FC4C02", domain: "strava.com"),

        // ── Telecom (global brands simple-icons carries) ─────────
        Brand(id: "vodafone", matchKeys: ["vodafone"], displayName: "Vodafone",
              tintHex: "E60000", domain: "vodafone.ie"),
        Brand(id: "three", matchKeys: ["three mobile", "three ireland"],
              displayName: "Three", tintHex: "000000", domain: "three.ie"),
        Brand(id: "sky", matchKeys: ["sky "], displayName: "Sky",
              tintHex: "0072C9", domain: "sky.com"),

        // ── Irish regional — no simple-icons mark, logo-API tier ─
        Brand(id: "gomo", matchKeys: ["gomo"], displayName: "GoMo",
              tintHex: "00B5A0", domain: "gomo.ie"),
        Brand(id: "eir", matchKeys: ["eir"], displayName: "Eir",
              tintHex: "8223D2", domain: "eir.ie"),
        Brand(id: "electricireland", matchKeys: ["electric ireland"],
              displayName: "Electric Ireland", tintHex: "E4002B", domain: "electricireland.ie"),
        Brand(id: "bordgais", matchKeys: ["bord gáis", "bord gais"],
              displayName: "Bord Gáis Energy", tintHex: "00A0DF", domain: "bordgaisenergy.ie"),
        Brand(id: "virginmedia", matchKeys: ["virgin media"], displayName: "Virgin Media",
              tintHex: "E10A0A", domain: "virginmedia.ie"),
        Brand(id: "flyefit", matchKeys: ["flyefit"], displayName: "FlyeFit",
              tintHex: "E4002B", domain: "flyefit.ie")
    ]

    /// First brand whose match keys appear in `name`. Longer keys are
    /// tried first so "apple music" wins over a bare "apple" (there
    /// is no bare "apple" key, but the principle guards future ones).
    static func match(name: String) -> Brand? {
        let n = name.lowercased()
        return all
            .flatMap { brand in brand.matchKeys.map { (brand, $0) } }
            .sorted { $0.1.count > $1.1.count }
            .first { n.contains($0.1) }?
            .0
    }
}
