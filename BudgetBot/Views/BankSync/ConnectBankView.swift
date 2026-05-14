import SwiftUI

/// "Connect a bank" entry. Today this is intentionally a holding page —
/// the underlying `BankSyncProvider` is a `Stub` until we have a
/// commercial agreement with Tink/TrueLayer/Plaid + production
/// credentials. The page exists so the surface is wired and we don't
/// have to redesign navigation when the integration lands.
struct ConnectBankView: View {
    @Environment(ThemeManager.self) private var theme

    private var provider: any BankSyncProvider { BankSyncRegistry.active }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                providerCard
                whatsNext
                whyItMatters
                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Connect a bank")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.current.tint)
                .breathingPulse(amplitude: 0.04, period: 3.2)
            Text("Bank sync — in procurement")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Receipts are great for the moments you remember to scan. Bank sync is for everything else — rent, bills, subscriptions, the coffee you forgot. Coming once the commercial agreement is in place.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Provider card

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active provider").font(.caption.bold())
                    .tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                Text(provider.isConfigured ? "Configured" : "Stub")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(
                        (provider.isConfigured ? Color.green : Color.orange).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(provider.isConfigured ? .green : .orange)
            }
            HStack {
                Image(systemName: "tray.full.fill")
                    .font(.title3)
                    .foregroundStyle(theme.current.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName).font(.headline)
                    Text(provider.isConfigured
                         ? "Tap Connect to link a bank."
                         : "Awaiting commercial agreement + production credentials.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button {
                // No-op until configured.
            } label: {
                Text(provider.isConfigured ? "Connect a bank" : "Coming soon")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        provider.isConfigured
                            ? AnyShapeStyle(theme.current.tint)
                            : AnyShapeStyle(.gray.opacity(0.3)),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!provider.isConfigured)
        }
        .padding(18)
        .themedCard()
    }

    // MARK: - What's next

    private var whatsNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's next").font(.headline)
            bullet("KYC + business-entity verification with the chosen aggregator (Tink in IE/EU first, TrueLayer for UK).")
            bullet("PSD2 AISP (Account Information Service Provider) scope on the aggregator agreement.")
            bullet("Production API credentials stored in Keychain, never bundled.")
            bullet("Initial back-fill of 90 days of transactions per linked account, then nightly delta pulls.")
            bullet("AI categorisation runs against bank-supplied descriptions to fill the gaps the bank's own categories miss.")
        }
        .padding(18)
        .themedCard()
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(theme.current.tint)
            Text(s)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Why

    private var whyItMatters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why we don't bundle keys").font(.subheadline.bold())
            Text("Bundling production aggregator credentials in an App Store binary is bad for safety (keys can be extracted) and bad commercially (per-call cost lives in the binary). The agreement-first approach also lets us pick the right partner for our user base instead of locking into the cheapest demo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .themedCard()
    }
}
