import SwiftUI

/// Circular brand badge for a subscription. Two tiers:
///
///   1. **Real logo** — the brand's own icon, fetched once by domain
///      from a free favicon service and cached to disk (App Group
///      container), so it's instant and offline on every later view.
///   2. **SF Symbol** — `SubscriptionStyle`'s category glyph. The
///      fallback while the logo is still loading, when offline on
///      first sight, or when the brand isn't in `BrandCatalog`.
struct BrandLogoView: View {
    let subscriptionName: String
    var categoryName: String? = nil
    var size: CGFloat = 40

    @State private var logo: UIImage?

    private var brand: Brand? { BrandCatalog.match(name: subscriptionName) }

    var body: some View {
        ZStack { badge }
            .frame(width: size, height: size)
            .task(id: subscriptionName) {
                guard let domain = brand?.domain else { return }
                logo = await BrandLogoStore.logo(forDomain: domain)
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
        } else {
            // Tier 2 — SF Symbol fallback.
            let style = SubscriptionStyle.resolve(
                name: subscriptionName, categoryName: categoryName)
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
