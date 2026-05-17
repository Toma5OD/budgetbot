import SwiftUI

/// Circular brand badge for a subscription. Resolves through four
/// tiers, each degrading cleanly into the next:
///
///   1. **Bundled mark** — a CC0 simple-icons glyph in the asset
///      catalog, white on the brand's official colour. Instant,
///      offline, covers the big global brands.
///   2. **Disk-cached logo** — a full-colour logo fetched earlier by
///      the logo-API tier and kept in the App Group container.
///      Instant, offline, zero network.
///   3. **Freshly-fetched logo** — for a brand seen for the first
///      time, fetched once from the logo API (if a token is set),
///      then written to the disk cache so step 2 covers it forever.
///   4. **SF Symbol** — `SubscriptionStyle`'s category glyph, the
///      universal fallback when offline + uncached + unknown.
struct BrandLogoView: View {
    let subscriptionName: String
    var categoryName: String? = nil
    var size: CGFloat = 40

    @State private var fetched: UIImage?

    private var brand: Brand? { BrandCatalog.match(name: subscriptionName) }
    private var bundledMark: UIImage? {
        brand.flatMap { UIImage(named: $0.assetName) }
    }

    var body: some View {
        ZStack { badge }
            .frame(width: size, height: size)
            .task(id: subscriptionName) {
                // Only the remote tier needs async work — bundled
                // marks and the SF fallback resolve synchronously.
                guard bundledMark == nil, let domain = brand?.domain else { return }
                fetched = await BrandLogoStore.logo(forDomain: domain)
            }
    }

    @ViewBuilder
    private var badge: some View {
        if let mark = bundledMark, let brand {
            // Tier 1 — bundled CC0 mark, white on the brand colour.
            Circle()
                .fill(LinearGradient(
                    colors: [brand.tint, brand.tint.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(uiImage: mark)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(size * 0.26)
        } else if let fetched {
            // Tier 2/3 — full-colour logo from the API tier, cached
            // to disk. Sits on a neutral chip so light logos read.
            Circle().fill(Color(.secondarySystemBackground))
            Image(uiImage: fetched)
                .resizable()
                .scaledToFit()
                .padding(size * 0.16)
                .clipShape(Circle())
        } else {
            // Tier 4 — SF Symbol fallback.
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
