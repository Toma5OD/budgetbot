import SwiftUI
import SwiftData

/// The "Fun" hub — a real, discoverable home for BudgetBot's playful /
/// game-y features, rather than burying them in Settings (Settings is
/// for configuration; a swipe-to-rate game and a Hall of Shame are
/// features). Reached from the Home quick-action row.
///
/// Collects four things:
///   - **Rate in Hindsight** — the swipe-deck rating game.
///   - **Hall of Shame** — your worst purchases, ranked.
///   - **Savings Goals** — funded targets with progress rings.
///   - **My Dreams** — reference prices that power the "what it
///     could've been" counterfactuals.
///
/// Each card carries a live count badge so the hub itself tells you
/// where there's something to do.
struct FunHubView: View {
    @Environment(ThemeManager.self) private var theme

    @Query(
        filter: #Predicate<Transaction> {
            $0.confirmed && $0.hindsightRating == nil && $0.amount < 0
        }
    )
    private var unrated: [Transaction]

    @Query(filter: #Predicate<Transaction> { $0.confirmed && $0.isRegret })
    private var regrets: [Transaction]

    @Query private var goals: [SavingsGoal]
    @Query private var dreams: [UserDream]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                hubCard(
                    title: "Rate in Hindsight",
                    subtitle: "Score past purchases 1–5 in a quick swipe game.",
                    icon: "star.leadinghalf.filled",
                    tint: .orange,
                    badge: unrated.isEmpty ? nil : "\(unrated.count) to rate"
                ) { HindsightReviewView() }

                hubCard(
                    title: "Hall of Shame",
                    subtitle: "Your stupidest purchases, ranked by damage.",
                    icon: "trophy.fill",
                    tint: .pink,
                    badge: regrets.isEmpty ? nil : "\(regrets.count)"
                ) { HallOfShameView() }

                hubCard(
                    title: "Savings Goals",
                    subtitle: "Set a target, log contributions, watch the ring fill.",
                    icon: "target",
                    tint: .green,
                    badge: goals.isEmpty ? nil : "\(goals.count)"
                ) { SavingsGoalsView() }

                hubCard(
                    title: "My Dreams",
                    subtitle: "Ring, house deposit, M3 — what your spending could've been.",
                    icon: "sparkles",
                    tint: .yellow,
                    badge: dreams.isEmpty ? nil : "\(dreams.count)"
                ) { DreamsView() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Fun")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "die.face.5.fill")
                .font(.system(size: 30))
                .foregroundStyle(theme.current.tint)
                .breathingPulse(amplitude: 0.05, period: 3.0)
            Text("The bits of budgeting that don't feel like budgeting.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Card

    @ViewBuilder
    private func hubCard<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        badge: String?,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [tint, tint.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(tint)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .themedCard()
        }
        .buttonStyle(.pressable)
    }
}
