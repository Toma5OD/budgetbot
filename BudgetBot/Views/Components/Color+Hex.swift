import SwiftUI

extension Color {
    /// Builds a `Color` from a hex string — `"E50914"`, `"#E50914"`,
    /// or an 8-digit `"AARRGGBB"` form. Falls back to `.gray` for
    /// anything unparseable so a bad value can never crash a view.
    init(hex raw: String) {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }

        let r, g, b, a: Double
        switch cleaned.count {
        case 6:   // RRGGBB
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double( value & 0x0000FF) / 255
            a = 1
        case 8:   // AARRGGBB
            a = Double((value & 0xFF000000) >> 24) / 255
            r = Double((value & 0x00FF0000) >> 16) / 255
            g = Double((value & 0x0000FF00) >> 8) / 255
            b = Double( value & 0x000000FF) / 255
        default:
            self = .gray
            return
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
