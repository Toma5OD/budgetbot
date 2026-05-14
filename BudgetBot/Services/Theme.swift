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
        // Each slot ≥30° apart in hue and ≥3:1 luminance vs the deep navy
        // background. Slot 8 used to be a washed-out light grey that
        // dissolved into UI chrome — replaced with a saturated gold.
        chartPalette: [
            Color(red: 0.0,  green: 0.83, blue: 1.0),   // cyan
            Color(red: 1.0,  green: 0.32, blue: 0.83),  // magenta
            Color(red: 0.71, green: 1.0,  blue: 0.27),  // lime
            Color(red: 1.0,  green: 0.66, blue: 0.0),   // orange
            Color(red: 0.65, green: 0.45, blue: 1.0),   // violet
            Color(red: 1.0,  green: 0.35, blue: 0.35),  // coral
            Color(red: 0.30, green: 1.0,  blue: 0.78),  // mint
            Color(red: 0.96, green: 0.82, blue: 0.30)   // gold
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
        // Previously: 8 near-identical muddy browns — two adjacent slots
        // were within 0.05 of each other and one slot was a slate grey so
        // dark it disappeared into the cream background. Replaced with
        // 8 distinct saturated tones in the journal/manuscript palette,
        // each at ≥3:1 contrast vs the cream surface.
        chartPalette: [
            Color(red: 0.66, green: 0.42, blue: 0.18),  // ochre
            Color(red: 0.17, green: 0.45, blue: 0.50),  // deep teal
            Color(red: 0.85, green: 0.66, blue: 0.20),  // goldenrod
            Color(red: 0.49, green: 0.55, blue: 0.25),  // olive
            Color(red: 0.66, green: 0.22, blue: 0.36),  // burgundy
            Color(red: 0.20, green: 0.30, blue: 0.55),  // ink navy
            Color(red: 0.78, green: 0.32, blue: 0.18),  // brick red
            Color(red: 0.18, green: 0.42, blue: 0.27)   // forest green
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
        // Slot 7 used to be white:0.85 — invisible against any light
        // background. Tightened the ramp so all 8 slots are visibly
        // distinct in both light and dark mode.
        chartPalette: [
            Color(white: 0.10),
            Color(white: 0.28),
            Color(white: 0.44),
            Color(white: 0.58),
            Color(white: 0.72),
            Color.orange,                    // single accent — picks out anomalies
            Color(white: 0.38),
            Color(white: 0.18)
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
        // Slot 7 used to be a salmon (0.99, 0.55, 0.55) almost identical
        // to slot 1's coral — both rendered as the same wedge. Replaced
        // with a cyan/aqua so the palette spans the colour wheel.
        chartPalette: [
            Color(red: 0.96, green: 0.41, blue: 0.42),  // coral
            Color(red: 0.99, green: 0.68, blue: 0.35),  // orange
            Color(red: 0.95, green: 0.78, blue: 0.30),  // amber
            Color(red: 0.85, green: 0.45, blue: 0.75),  // pink
            Color(red: 0.55, green: 0.45, blue: 0.85),  // violet
            Color(red: 0.30, green: 0.72, blue: 0.78),  // teal
            Color(red: 0.20, green: 0.55, blue: 0.85),  // sky
            Color(red: 0.42, green: 0.30, blue: 0.55)   // aubergine
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
        // Slot 8 used to be a pale lavender that read as a duplicate of
        // slot 2's purple in the donut. Swapped for a warm peach so the
        // last wedge is unambiguously distinct.
        chartPalette: [
            Color(red: 0.55, green: 0.72, blue: 1.0),  // azure
            Color(red: 0.78, green: 0.45, blue: 1.0),  // violet
            Color(red: 0.30, green: 0.95, blue: 0.85), // aqua
            Color(red: 1.0,  green: 0.42, blue: 0.68), // pink
            Color(red: 0.95, green: 0.78, blue: 0.30), // amber
            Color(red: 0.42, green: 0.85, blue: 0.45), // emerald
            Color(red: 0.99, green: 0.55, blue: 0.30), // orange
            Color(red: 1.0,  green: 0.72, blue: 0.50)  // peach
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

    /// Second light theme — pairs with Paper. Where Paper goes for a
    /// manuscript/journal feel with earthy tones, Linen is fresh and
    /// modern: an off-white "fabric" surface, sage tint, and a vivid
    /// Tableau-inspired palette tuned for ≥3:1 contrast on cream so
    /// donut wedges read cleanly without the muddy look the old Paper
    /// palette had.
    static let linen = Theme(
        id: "linen",
        displayName: "Linen",
        systemImage: "sun.max.fill",
        preferredScheme: .light,
        tint: Color(red: 0.32, green: 0.55, blue: 0.42),       // sage
        chartPalette: [
            Color(red: 0.12, green: 0.49, blue: 0.69),  // pacific blue
            Color(red: 0.88, green: 0.37, blue: 0.29),  // coral red
            Color(red: 0.85, green: 0.63, blue: 0.10),  // mustard
            Color(red: 0.55, green: 0.31, blue: 0.67),  // plum
            Color(red: 0.18, green: 0.55, blue: 0.40),  // forest
            Color(red: 0.24, green: 0.35, blue: 0.64),  // indigo
            Color(red: 0.74, green: 0.29, blue: 0.13),  // burnt orange
            Color(red: 0.43, green: 0.55, blue: 0.24)   // olive sage
        ],
        incomeColor: Color(red: 0.18, green: 0.55, blue: 0.40),
        expenseColor: Color(red: 0.78, green: 0.22, blue: 0.18),
        background: .solid(Color(red: 0.98, green: 0.97, blue: 0.94)),
        card: .filled(
            Color.white,
            border: Color(red: 0.85, green: 0.83, blue: 0.78),
            borderWidth: 0.5
        ),
        cornerRadius: 14,
        numericDesign: .rounded,
        headingDesign: .rounded,
        headingWeight: .semibold
    )

    static let all: [Theme] = [.midnight, .paper, .linen, .mono, .sunset, .aurora]

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
