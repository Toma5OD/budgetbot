import SwiftUI
import UIKit

/// A theme is more than colours. Each one defines a background paint, a card
/// style (frosted glass / solid fill / outlined / elevated), a corner radius,
/// a preferred colour scheme, the typography "feel", and the chart palette.
///
/// The point is for themes to look genuinely different — Midnight should feel
/// like a finance terminal, Paper should feel like a journal, Mono should
/// feel like a Swiss design poster. They are NOT five tints over the same
/// template.
struct Theme: Identifiable, Hashable {

    enum BackgroundStyle: Hashable {
        case solid(Color)
        case linearGradient(colors: [Color], from: UnitPoint, to: UnitPoint)
    }

    enum CardStyle: Hashable {
        /// Solid fill with optional border.
        case filled(Color, border: Color? = nil, borderWidth: CGFloat = 0)
        /// Built-in SwiftUI material (.ultraThinMaterial etc).
        case frosted(level: FrostLevel, border: Color? = nil, borderWidth: CGFloat = 0)
        /// Transparent with prominent border. Used for the brutalist Mono theme.
        case outlined(border: Color, borderWidth: CGFloat)
    }

    enum FrostLevel: Hashable {
        case ultraThin, thin, regular, thick
    }

    let id: String
    let displayName: String
    let systemImage: String

    let preferredScheme: ColorScheme?    // nil = follow system

    // Foreground
    let tint: Color
    let chartPalette: [Color]
    let incomeColor: Color
    let expenseColor: Color

    // Surfaces
    let background: BackgroundStyle
    let card: CardStyle
    let cornerRadius: CGFloat

    // Typography "feel" — Font.Design, applied to numerics + headings via
    // helpers in Theme+Modifiers.swift.
    let numericDesign: Font.Design
    let headingDesign: Font.Design
    let headingWeight: Font.Weight

    // MARK: - Catalogue

    static let midnight = Theme(
        id: "midnight",
        displayName: "Midnight",
        systemImage: "moon.stars.fill",
        preferredScheme: .dark,
        tint: Color(red: 0.0, green: 0.83, blue: 1.0),
        chartPalette: [
            Color(red: 0.0,  green: 0.83, blue: 1.0),   // cyan
            Color(red: 1.0,  green: 0.32, blue: 0.83),  // magenta
            Color(red: 0.71, green: 1.0,  blue: 0.27),  // lime
            Color(red: 1.0,  green: 0.66, blue: 0.0),   // orange
            Color(red: 0.65, green: 0.45, blue: 1.0),   // violet
            Color(red: 1.0,  green: 0.35, blue: 0.35),  // coral
            Color(red: 0.30, green: 1.0,  blue: 0.78),  // mint
            Color(red: 0.85, green: 0.85, blue: 0.85)   // light grey
        ],
        incomeColor: Color(red: 0.30, green: 1.0, blue: 0.78),
        expenseColor: Color(red: 1.0,  green: 0.35, blue: 0.45),
        background: .linearGradient(
            colors: [Color(red: 0.04, green: 0.05, blue: 0.10),
                     Color(red: 0.02, green: 0.02, blue: 0.05)],
            from: .top, to: .bottom
        ),
        card: .frosted(level: .ultraThin, border: Color.white.opacity(0.08), borderWidth: 0.5),
        cornerRadius: 18,
        numericDesign: .monospaced,
        headingDesign: .default,
        headingWeight: .semibold
    )

    static let paper = Theme(
        id: "paper",
        displayName: "Paper",
        systemImage: "doc.text.fill",
        preferredScheme: .light,
        tint: Color(red: 0.66, green: 0.42, blue: 0.18),       // ochre
        chartPalette: [
            Color(red: 0.66, green: 0.42, blue: 0.18),
            Color(red: 0.45, green: 0.32, blue: 0.18),
            Color(red: 0.85, green: 0.62, blue: 0.28),
            Color(red: 0.52, green: 0.55, blue: 0.30),
            Color(red: 0.68, green: 0.45, blue: 0.35),
            Color(red: 0.32, green: 0.42, blue: 0.45),
            Color(red: 0.78, green: 0.55, blue: 0.45),
            Color(red: 0.40, green: 0.30, blue: 0.20)
        ],
        incomeColor: Color(red: 0.32, green: 0.50, blue: 0.30),
        expenseColor: Color(red: 0.75, green: 0.28, blue: 0.20),
        background: .solid(Color(red: 0.96, green: 0.93, blue: 0.86)),
        card: .filled(
            Color(red: 1.0, green: 0.99, blue: 0.95),
            border: Color(red: 0.78, green: 0.68, blue: 0.50).opacity(0.35),
            borderWidth: 0.5
        ),
        cornerRadius: 10,
        numericDesign: .serif,
        headingDesign: .serif,
        headingWeight: .semibold
    )

    static let mono = Theme(
        id: "mono",
        displayName: "Mono",
        systemImage: "circle.righthalf.filled",
        preferredScheme: nil,
        tint: Color.primary,
        chartPalette: [
            Color(white: 0.10),
            Color(white: 0.30),
            Color(white: 0.45),
            Color(white: 0.60),
            Color(white: 0.75),
            Color.orange,                    // single accent — picks out anomalies
            Color(white: 0.85),
            Color(white: 0.20)
        ],
        incomeColor: Color.primary,
        expenseColor: Color.primary,
        background: .solid(Color(UIColor.systemBackground)),
        card: .outlined(border: Color.primary.opacity(0.85), borderWidth: 1.5),
        cornerRadius: 0,
        numericDesign: .monospaced,
        headingDesign: .default,
        headingWeight: .black
    )

    static let sunset = Theme(
        id: "sunset",
        displayName: "Sunset",
        systemImage: "sun.horizon.fill",
        preferredScheme: nil,
        tint: Color(red: 0.96, green: 0.41, blue: 0.42),       // coral
        chartPalette: [
            Color(red: 0.96, green: 0.41, blue: 0.42),
            Color(red: 0.99, green: 0.68, blue: 0.35),
            Color(red: 0.99, green: 0.85, blue: 0.40),
            Color(red: 0.85, green: 0.45, blue: 0.75),
            Color(red: 0.55, green: 0.45, blue: 0.85),
            Color(red: 0.45, green: 0.78, blue: 0.78),
            Color(red: 0.99, green: 0.55, blue: 0.55),
            Color(red: 0.78, green: 0.55, blue: 0.45)
        ],
        incomeColor: Color(red: 0.30, green: 0.72, blue: 0.55),
        expenseColor: Color(red: 0.96, green: 0.32, blue: 0.40),
        background: .linearGradient(
            colors: [Color(red: 1.0, green: 0.85, blue: 0.75),
                     Color(red: 1.0, green: 0.78, blue: 0.85),
                     Color(red: 0.88, green: 0.75, blue: 0.92)],
            from: .topLeading, to: .bottomTrailing
        ),
        card: .frosted(level: .regular, border: Color.white.opacity(0.4), borderWidth: 0.5),
        cornerRadius: 22,
        numericDesign: .rounded,
        headingDesign: .rounded,
        headingWeight: .bold
    )

    static let aurora = Theme(
        id: "aurora",
        displayName: "Aurora",
        systemImage: "sparkles",
        preferredScheme: .dark,
        tint: Color(red: 0.55, green: 0.72, blue: 1.0),
        chartPalette: [
            Color(red: 0.55, green: 0.72, blue: 1.0),
            Color(red: 0.78, green: 0.45, blue: 1.0),
            Color(red: 0.30, green: 0.95, blue: 0.85),
            Color(red: 1.0,  green: 0.42, blue: 0.68),
            Color(red: 0.95, green: 0.78, blue: 0.30),
            Color(red: 0.42, green: 0.85, blue: 0.45),
            Color(red: 0.99, green: 0.55, blue: 0.30),
            Color(red: 0.72, green: 0.55, blue: 0.95)
        ],
        incomeColor: Color(red: 0.30, green: 0.95, blue: 0.85),
        expenseColor: Color(red: 1.0,  green: 0.42, blue: 0.55),
        background: .linearGradient(
            colors: [Color(red: 0.10, green: 0.05, blue: 0.30),
                     Color(red: 0.18, green: 0.08, blue: 0.42),
                     Color(red: 0.36, green: 0.12, blue: 0.55),
                     Color(red: 0.08, green: 0.05, blue: 0.20)],
            from: .topLeading, to: .bottomTrailing
        ),
        card: .frosted(level: .thin, border: Color.white.opacity(0.18), borderWidth: 0.5),
        cornerRadius: 20,
        numericDesign: .rounded,
        headingDesign: .rounded,
        headingWeight: .semibold
    )

    static let all: [Theme] = [.midnight, .paper, .mono, .sunset, .aurora]

    static func by(id: String) -> Theme {
        all.first { $0.id == id } ?? .aurora
    }
}

/// Persists the user's theme choice. Same shape as the previous version so
/// existing call sites keep working.
@Observable
@MainActor
final class ThemeManager {
    private let key = "app.theme"
    private(set) var current: Theme

    init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? Theme.aurora.id
        self.current = Theme.by(id: raw)
    }

    func set(_ theme: Theme) {
        current = theme
        UserDefaults.standard.set(theme.id, forKey: key)
    }
}
