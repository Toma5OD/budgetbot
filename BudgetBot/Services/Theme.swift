import SwiftUI

/// User-pickable themes. Each carries an accent (used as `.tint`), a contrast
/// secondary accent, and a chart palette so the pie / bar charts get a coherent
/// set of colours rather than SwiftUI's default rainbow.
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case indigo, forest, sunset, ocean, berry, mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indigo:  return "Indigo"
        case .forest:  return "Forest"
        case .sunset:  return "Sunset"
        case .ocean:   return "Ocean"
        case .berry:   return "Berry"
        case .mono:    return "Mono"
        }
    }

    /// Symbol used in the theme picker preview tile.
    var systemImage: String {
        switch self {
        case .indigo:  return "sparkles"
        case .forest:  return "leaf.fill"
        case .sunset:  return "sun.horizon.fill"
        case .ocean:   return "water.waves"
        case .berry:   return "heart.fill"
        case .mono:    return "circle.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .indigo:  return Color(red: 0.40, green: 0.36, blue: 0.86)
        case .forest:  return Color(red: 0.13, green: 0.65, blue: 0.42)
        case .sunset:  return Color(red: 0.95, green: 0.45, blue: 0.30)
        case .ocean:   return Color(red: 0.10, green: 0.62, blue: 0.78)
        case .berry:   return Color(red: 0.83, green: 0.30, blue: 0.55)
        case .mono:    return Color(red: 0.30, green: 0.30, blue: 0.32)
        }
    }

    var tintSecondary: Color {
        switch self {
        case .indigo:  return Color(red: 0.62, green: 0.55, blue: 0.95)
        case .forest:  return Color(red: 0.30, green: 0.78, blue: 0.55)
        case .sunset:  return Color(red: 0.98, green: 0.68, blue: 0.34)
        case .ocean:   return Color(red: 0.30, green: 0.82, blue: 0.90)
        case .berry:   return Color(red: 0.95, green: 0.55, blue: 0.78)
        case .mono:    return Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }

    /// Up to 8 colors used by the charts for category-coloured marks.
    var chartPalette: [Color] {
        switch self {
        case .indigo:
            return [
                Color(red: 0.40, green: 0.36, blue: 0.86),
                Color(red: 0.62, green: 0.55, blue: 0.95),
                Color(red: 0.30, green: 0.65, blue: 0.95),
                Color(red: 0.95, green: 0.65, blue: 0.30),
                Color(red: 0.95, green: 0.45, blue: 0.55),
                Color(red: 0.30, green: 0.80, blue: 0.65),
                Color(red: 0.78, green: 0.45, blue: 0.95),
                Color(red: 0.55, green: 0.55, blue: 0.58)
            ]
        case .forest:
            return [
                Color(red: 0.13, green: 0.65, blue: 0.42),
                Color(red: 0.55, green: 0.78, blue: 0.42),
                Color(red: 0.90, green: 0.75, blue: 0.20),
                Color(red: 0.85, green: 0.45, blue: 0.15),
                Color(red: 0.30, green: 0.55, blue: 0.65),
                Color(red: 0.70, green: 0.45, blue: 0.25),
                Color(red: 0.50, green: 0.65, blue: 0.30),
                Color(red: 0.40, green: 0.50, blue: 0.40)
            ]
        case .sunset:
            return [
                Color(red: 0.95, green: 0.45, blue: 0.30),
                Color(red: 0.98, green: 0.68, blue: 0.34),
                Color(red: 0.95, green: 0.85, blue: 0.40),
                Color(red: 0.85, green: 0.35, blue: 0.55),
                Color(red: 0.65, green: 0.35, blue: 0.75),
                Color(red: 0.95, green: 0.55, blue: 0.65),
                Color(red: 0.80, green: 0.60, blue: 0.45),
                Color(red: 0.55, green: 0.40, blue: 0.50)
            ]
        case .ocean:
            return [
                Color(red: 0.10, green: 0.62, blue: 0.78),
                Color(red: 0.30, green: 0.82, blue: 0.90),
                Color(red: 0.20, green: 0.45, blue: 0.78),
                Color(red: 0.55, green: 0.78, blue: 0.85),
                Color(red: 0.65, green: 0.50, blue: 0.85),
                Color(red: 0.35, green: 0.80, blue: 0.65),
                Color(red: 0.95, green: 0.65, blue: 0.45),
                Color(red: 0.45, green: 0.55, blue: 0.65)
            ]
        case .berry:
            return [
                Color(red: 0.83, green: 0.30, blue: 0.55),
                Color(red: 0.95, green: 0.55, blue: 0.78),
                Color(red: 0.55, green: 0.30, blue: 0.78),
                Color(red: 0.30, green: 0.55, blue: 0.85),
                Color(red: 0.95, green: 0.45, blue: 0.45),
                Color(red: 0.55, green: 0.78, blue: 0.55),
                Color(red: 0.85, green: 0.65, blue: 0.35),
                Color(red: 0.45, green: 0.45, blue: 0.55)
            ]
        case .mono:
            return [
                Color(red: 0.20, green: 0.22, blue: 0.25),
                Color(red: 0.40, green: 0.42, blue: 0.45),
                Color(red: 0.55, green: 0.58, blue: 0.62),
                Color(red: 0.70, green: 0.72, blue: 0.75),
                Color(red: 0.85, green: 0.55, blue: 0.30),
                Color(red: 0.30, green: 0.30, blue: 0.32),
                Color(red: 0.62, green: 0.62, blue: 0.65),
                Color(red: 0.95, green: 0.65, blue: 0.30)
            ]
        }
    }

    var incomeColor: Color { Color(red: 0.20, green: 0.72, blue: 0.50) }
    var expenseColor: Color { Color(red: 0.90, green: 0.35, blue: 0.40) }
}

/// Observed wrapper that persists the user's theme choice across launches.
@Observable
@MainActor
final class ThemeManager {
    private let key = "app.theme"
    private(set) var current: AppTheme

    init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppTheme.indigo.rawValue
        self.current = AppTheme(rawValue: raw) ?? .indigo
    }

    func set(_ theme: AppTheme) {
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}
