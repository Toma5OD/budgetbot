import SwiftUI

/// iOS-Settings-style row: coloured icon tile + title + optional subtitle/value
/// + optional accessory. Used in Settings, Profile, and anywhere we want the
/// "this is a thing you can tap" pattern without rolling our own each time.
struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconTint: Color
    @ViewBuilder let accessory: () -> Accessory

    init(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        tint: Color,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = tint
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: icon, tint: iconTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            accessory()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 28×28 rounded coloured square with a white SF Symbol — the iOS Settings
/// "app icon" tile.
struct IconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Section header in the all-caps tracked style iOS Settings uses.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }
}

/// Rounded card wrapping a vertical stack of rows. Use for grouping rows in
/// the new Settings/Profile screens. Dividers are inset to match iOS.
struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .padding(.horizontal, 16)
    }
}

/// Standard inset divider between rows inside a GroupedCard.
struct RowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14 + 28)   // icon width + spacing — aligns under text
    }
}
