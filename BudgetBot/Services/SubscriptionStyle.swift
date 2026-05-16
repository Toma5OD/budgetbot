import SwiftUI

/// Picks a representative SF Symbol + tint for a subscription so the
/// Subscriptions screen reads at a glance — a TV glyph for Netflix, a
/// signal glyph for a phone plan, a flame for the gas bill.
///
/// We deliberately do *not* bundle real brand logos: that's a
/// trademark problem and a maintenance treadmill (logos get redrawn,
/// brands get acquired). SF Symbols keyed to the *kind* of service get
/// most of the recognisability for none of the risk, and they recolour
/// cleanly for light/dark + every app theme.
///
/// Resolution order: match the display name first (most specific),
/// then the linked category, then fall back to a generic recurring
/// glyph.
enum SubscriptionStyle {

    struct Style: Equatable {
        let symbol: String
        let tint: Color
    }

    static let generic = Style(symbol: "arrow.triangle.2.circlepath", tint: .gray)

    static func resolve(name: String, categoryName: String? = nil) -> Style {
        let n = name.lowercased()

        // Broadband first — "Eir Broadband" and "Eir Mobile" share the
        // "eir" token, so the internet check has to win before mobile.
        if contains(n, ["broadband", "fibre", "fiber", "virgin media",
                        "sky broadband", "wifi", "wi-fi"]) {
            return Style(symbol: "wifi", tint: .teal)
        }
        if contains(n, ["gomo", "vodafone", "three mobile", "tesco mobile",
                        "id mobile", "lycamobile", "sky mobile", "eir mobile",
                        "mobile plan", "phone plan", "giffgaff", "ee mobile"]) {
            return Style(symbol: "antenna.radiowaves.left.and.right", tint: .blue)
        }
        if contains(n, ["netflix", "disney", "now tv", "prime video",
                        "apple tv", "paramount", "hbo", "hayu", "peacock",
                        "britbox", "mubi"]) {
            return Style(symbol: "play.tv.fill", tint: .red)
        }
        if contains(n, ["youtube"]) {
            return Style(symbol: "play.rectangle.fill", tint: .red)
        }
        if contains(n, ["spotify", "apple music", "tidal", "deezer",
                        "soundcloud", "amazon music", "youtube music"]) {
            return Style(symbol: "music.note", tint: .green)
        }
        if contains(n, ["audible", "kindle", "scribd", "blinkist", "storytel"]) {
            return Style(symbol: "headphones", tint: .orange)
        }
        if contains(n, ["gym", "flyefit", "anytime fitness", "puregym",
                        "westwood", "ben dunne", "icon health", "fitness",
                        "strava", "peloton", "f45"]) {
            return Style(symbol: "figure.run", tint: .orange)
        }
        // Gas / heating before electricity — "Bord Gáis Energy" sells
        // both but reads as a gas brand.
        if contains(n, ["bord gáis", "bord gais", "calor", "flogas",
                        "heating", "natural gas"]) {
            return Style(symbol: "flame.fill", tint: .orange)
        }
        if contains(n, ["electric ireland", "electricity", "sse airtricity",
                        "energia", "pinergy", "prepaypower", "power ni"]) {
            return Style(symbol: "bolt.fill", tint: .yellow)
        }
        if contains(n, ["irish water", "uisce", "water"]) {
            return Style(symbol: "drop.fill", tint: .blue)
        }
        if contains(n, ["insurance", "aviva", "axa", "zurich", "vhi",
                        "laya", "allianz", "fbd", "irish life"]) {
            return Style(symbol: "checkmark.shield.fill", tint: .indigo)
        }
        if contains(n, ["icloud", "dropbox", "google one", "google drive",
                        "onedrive", "backblaze"]) {
            return Style(symbol: "icloud.fill", tint: .blue)
        }
        if contains(n, ["adobe", "microsoft 365", "office 365", "notion",
                        "1password", "github", "chatgpt", "claude",
                        "figma", "canva", "linkedin premium"]) {
            return Style(symbol: "app.badge.fill", tint: .purple)
        }
        if contains(n, ["irish times", "independent", "the journal",
                        "new york times", "nyt", "guardian", "economist",
                        "patreon", "substack", "medium"]) {
            return Style(symbol: "newspaper.fill", tint: .brown)
        }

        // No name hit — fall back to the linked category.
        return categoryStyle(categoryName)
    }

    // MARK: - Category fallback

    private static func categoryStyle(_ categoryName: String?) -> Style {
        switch categoryName?.lowercased() {
        case "streaming":
            return Style(symbol: "play.tv.fill", tint: .red)
        case "mobile plan":
            return Style(symbol: "antenna.radiowaves.left.and.right", tint: .blue)
        case "internet":
            return Style(symbol: "wifi", tint: .teal)
        case "electricity":
            return Style(symbol: "bolt.fill", tint: .yellow)
        case "heating & gas":
            return Style(symbol: "flame.fill", tint: .orange)
        case "water":
            return Style(symbol: "drop.fill", tint: .blue)
        case "insurance":
            return Style(symbol: "checkmark.shield.fill", tint: .indigo)
        case "books & media":
            return Style(symbol: "book.fill", tint: .brown)
        default:
            return generic
        }
    }

    // MARK: - Helpers

    private static func contains(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
