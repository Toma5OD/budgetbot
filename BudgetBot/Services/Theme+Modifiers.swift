import SwiftUI

// MARK: - Background

extension Theme.BackgroundStyle {
    @ViewBuilder
    var view: some View {
        switch self {
        case .solid(let c):
            c.ignoresSafeArea()
        case .linearGradient(let colors, let from, let to):
            LinearGradient(colors: colors, startPoint: from, endPoint: to)
                .ignoresSafeArea()
        }
    }
}

struct ThemedBackground: ViewModifier {
    let theme: Theme
    func body(content: Content) -> some View {
        ZStack {
            theme.background.view
            content
        }
    }
}

extension View {
    /// Paint the current theme's background under the view.
    func themedBackground(_ theme: Theme) -> some View {
        modifier(ThemedBackground(theme: theme))
    }
}

// MARK: - Cards

/// Apply the active theme's card style to any container. Replaces ad-hoc
/// `.background(.thinMaterial, in: RoundedRectangle(cornerRadius: ...))` calls.
struct ThemedCardStyle: ViewModifier {
    @Environment(ThemeManager.self) private var themeMgr

    func body(content: Content) -> some View {
        let t = themeMgr.current
        let shape = RoundedRectangle(cornerRadius: t.cornerRadius, style: .continuous)

        Group {
            switch t.card {
            case .filled(let fill, let border, let bw):
                content.background(fill, in: shape)
                    .overlay(shape.strokeBorder(border ?? .clear, lineWidth: bw))
            case .frosted(let level, let border, let bw):
                content.background(material(level), in: shape)
                    .overlay(shape.strokeBorder(border ?? .clear, lineWidth: bw))
            case .outlined(let border, let bw):
                content.background(Color.clear, in: shape)
                    .overlay(shape.strokeBorder(border, lineWidth: bw))
            }
        }
    }

    private func material(_ level: Theme.FrostLevel) -> Material {
        switch level {
        case .ultraThin: .ultraThinMaterial
        case .thin:      .thinMaterial
        case .regular:   .regularMaterial
        case .thick:     .thickMaterial
        }
    }
}

extension View {
    /// Wraps content in the active theme's card style. Pad internally before
    /// applying this if you want inset content.
    func themedCard() -> some View {
        modifier(ThemedCardStyle())
    }
}

// MARK: - Typography helpers

extension Theme {
    /// Use for currency, counts, percentages — anything that benefits from
    /// fixed-width digits or matches the theme's numeric vibe.
    func numericFont(_ size: Font, weight: Font.Weight = .regular) -> Font {
        // Font.system to combine size with design. We approximate by mapping
        // the chosen size to a system size + design.
        switch size {
        case .largeTitle:  return .system(size: 34, weight: weight, design: numericDesign)
        case .title:       return .system(size: 28, weight: weight, design: numericDesign)
        case .title2:      return .system(size: 22, weight: weight, design: numericDesign)
        case .title3:      return .system(size: 20, weight: weight, design: numericDesign)
        case .headline:    return .system(size: 17, weight: weight == .regular ? .semibold : weight, design: numericDesign)
        case .body:        return .system(size: 17, weight: weight, design: numericDesign)
        case .callout:     return .system(size: 16, weight: weight, design: numericDesign)
        case .subheadline: return .system(size: 15, weight: weight, design: numericDesign)
        case .footnote:    return .system(size: 13, weight: weight, design: numericDesign)
        case .caption:     return .system(size: 12, weight: weight, design: numericDesign)
        case .caption2:    return .system(size: 11, weight: weight, design: numericDesign)
        default:           return .system(size: 17, weight: weight, design: numericDesign)
        }
    }

    func headingFont(_ size: Font) -> Font {
        switch size {
        case .largeTitle:  return .system(size: 34, weight: headingWeight, design: headingDesign)
        case .title:       return .system(size: 28, weight: headingWeight, design: headingDesign)
        case .title2:      return .system(size: 22, weight: headingWeight, design: headingDesign)
        case .title3:      return .system(size: 20, weight: headingWeight, design: headingDesign)
        case .headline:    return .system(size: 17, weight: headingWeight, design: headingDesign)
        default:           return .system(size: 17, weight: headingWeight, design: headingDesign)
        }
    }
}
