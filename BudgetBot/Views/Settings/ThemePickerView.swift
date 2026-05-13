import SwiftUI

/// Theme picker. Each tile previews the theme in its actual style — background,
/// card, palette — so you can see what you're getting before you pick.
struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themeMgr

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Theme.all) { t in
                    ThemeTile(
                        theme: t,
                        isSelected: themeMgr.current.id == t.id
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            themeMgr.set(t)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemeTile: View {
    let theme: Theme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                preview
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? theme.tint : .clear, lineWidth: 3)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, theme.tint)
                                .padding(8)
                        }
                    }
                    .shadow(
                        color: theme.tint.opacity(isSelected ? 0.45 : 0.15),
                        radius: isSelected ? 12 : 6,
                        y: isSelected ? 6 : 3
                    )
                    .scaleEffect(isSelected ? 1.02 : 1.0)

                Text(theme.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme\(isSelected ? ", selected" : "")")
    }

    /// Renders the theme's actual background + a mock card + palette dots so
    /// the user sees the *vibe*, not just the tint.
    @ViewBuilder
    private var preview: some View {
        ZStack {
            theme.background.view

            VStack(spacing: 10) {
                // Mock "card"
                VStack(alignment: .leading, spacing: 6) {
                    Text("This month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("€1,247")
                        .font(.system(size: 22, weight: .bold, design: theme.numericDesign))
                        .foregroundStyle(theme.expenseColor)
                    HStack(spacing: 4) {
                        ForEach(Array(theme.chartPalette.prefix(5).enumerated()), id: \.offset) { _, c in
                            Circle().fill(c).frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(cardBackground)
                .overlay(cardBorder)
                .clipShape(RoundedRectangle(cornerRadius: max(theme.cornerRadius, 6), style: .continuous))

                // Title
                Text(theme.displayName.uppercased())
                    .font(.system(size: 11, weight: theme.headingWeight, design: theme.headingDesign))
                    .foregroundStyle(theme.tint)
                    .tracking(theme.id == "mono" ? 3 : 1)
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: max(theme.cornerRadius, 6), style: .continuous)
        switch theme.card {
        case .filled(let fill, _, _):
            shape.fill(fill)
        case .frosted(let level, _, _):
            switch level {
            case .ultraThin: shape.fill(.ultraThinMaterial)
            case .thin:      shape.fill(.thinMaterial)
            case .regular:   shape.fill(.regularMaterial)
            case .thick:     shape.fill(.thickMaterial)
            }
        case .outlined:
            shape.fill(Color.clear)
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        let shape = RoundedRectangle(cornerRadius: max(theme.cornerRadius, 6), style: .continuous)
        switch theme.card {
        case .filled(_, let border, let bw):
            shape.strokeBorder(border ?? .clear, lineWidth: bw)
        case .frosted(_, let border, let bw):
            shape.strokeBorder(border ?? .clear, lineWidth: bw)
        case .outlined(let border, let bw):
            shape.strokeBorder(border, lineWidth: bw)
        }
    }
}
