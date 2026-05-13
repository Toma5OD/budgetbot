import SwiftUI

/// Grid of theme tiles. Tap one → instantly applied across the app via the
/// shared ThemeManager + the root `.tint(...)` modifier.
struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var theme

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(AppTheme.allCases) { t in
                    ThemeTile(
                        theme: t,
                        isSelected: theme.current == t
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            theme.set(t)
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
    let theme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: [theme.tint, theme.tintSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    // Palette preview dots
                    HStack(spacing: 6) {
                        ForEach(Array(theme.chartPalette.prefix(5).enumerated()), id: \.offset) { _, c in
                            Circle().fill(c).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.5))
                        }
                    }
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .offset(y: 40)

                    Image(systemName: theme.systemImage)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 1)
                        .offset(y: -10)
                }
                .frame(height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 3)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, theme.tint)
                            .background(Circle().fill(.white).padding(4))
                            .padding(8)
                    }
                }
                .shadow(
                    color: theme.tint.opacity(isSelected ? 0.4 : 0.15),
                    radius: isSelected ? 12 : 6,
                    x: 0,
                    y: isSelected ? 6 : 3
                )
                .scaleEffect(isSelected ? 1.03 : 1.0)

                Text(theme.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme\(isSelected ? ", selected" : "")")
    }
}
