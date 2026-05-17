import SwiftUI

/// Circular brand badge for a merchant or subscription. Two tiers:
///
///   1. **Real logo** — the brand's own icon, fetched once by domain
///      from a free favicon service and cached to disk (App Group
///      container), so it's instant and offline on every later view.
///   2. **Fallback** — when the name isn't a known brand, or the logo
///      hasn't loaded yet. If `fallbackEmoji` is set (transaction rows
///      pass the category emoji) it's shown on a neutral chip;
///      otherwise `SubscriptionStyle`'s category SF Symbol is used.
struct BrandLogoView: View {
    /// Merchant or subscription name, matched against `BrandCatalog`.
    let name: String
    /// Feeds the `SubscriptionStyle` SF-Symbol fallback. Ignored when
    /// `fallbackEmoji` is supplied.
    var categoryName: String? = nil
    /// Shown on a neutral chip when there's no logo. When `nil`, the
    /// fallback is a `SubscriptionStyle` SF Symbol instead.
    var fallbackEmoji: String? = nil
    var size: CGFloat = 40

    @State private var logo: UIImage?

    private var brand: Brand? { BrandCatalog.match(name: name) }

    var body: some View {
        ZStack { badge }
            .frame(width: size, height: size)
            .task(id: name) {
                // Always resolve to the *current* name — clearing a
                // stale logo when the row is reused for another payee.
                if let domain = brand?.domain {
                    logo = await BrandLogoStore.logo(forDomain: domain)
                } else {
                    logo = nil
                }
            }
    }

    @ViewBuilder
    private var badge: some View {
        if let logo {
            // Tier 1 — real full-colour logo, on a neutral chip so
            // light logos still read against the card.
            Circle().fill(Color(.secondarySystemBackground))
            Image(uiImage: logo)
                .resizable()
                .scaledToFit()
                .padding(size * 0.16)
        } else if let fallbackEmoji {
            // Tier 2a — category emoji on the same neutral chip, so
            // branded and un-branded rows stay visually consistent.
            Circle().fill(Color(.secondarySystemBackground))
            Text(fallbackEmoji)
                .font(.system(size: size * 0.5))
        } else {
            // Tier 2b — SubscriptionStyle SF Symbol.
            let style = SubscriptionStyle.resolve(
                name: name, categoryName: categoryName)
            Circle()
                .fill(LinearGradient(
                    colors: [style.tint, style.tint.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: style.symbol)
                .font(.system(size: size * 0.42))
                .foregroundStyle(.white)
        }
    }
}
