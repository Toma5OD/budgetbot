import SwiftUI

/// First-launch welcome carousel. Three paged screens that explain what
/// the app does, plus a final "Get started" CTA that flips the
/// `hasCompletedWelcome` flag and dismisses.
///
/// Shown *before* sign-in so the user knows what they're signing up for.
/// `WelcomeFlow.hasCompletedWelcome` is exposed as a static var on the
/// type for convenience — RootView reads it to decide which root to
/// render.
struct WelcomeFlow: View {
    let onComplete: () -> Void

    @State private var page = 0
    @Environment(ThemeManager.self) private var theme

    private struct Page {
        let icon: String
        let title: String
        let body: String
        let tint: Color
    }

    private var pages: [Page] {
        [
            Page(icon: "camera.viewfinder",
                 title: "Snap anything",
                 body: "Receipts, PDFs, photos, screenshots, plain text — drop it in and the AI extracts the date, payee, total, line items and even the card brand.",
                 tint: theme.current.tint),
            Page(icon: "chart.pie.fill",
                 title: "Honest analytics",
                 body: "Need vs want. Brand tax. The drink tab. Hall of Shame. Your spending told straight, with the receipts to back it up.",
                 tint: .pink),
            Page(icon: "star.leadinghalf.filled",
                 title: "Rate. Reflect. Adjust.",
                 body: "Score past purchases 1-5 in hindsight. The data tightens the analytics; the swipe deck is the game.",
                 tint: .orange)
        ]
    }

    var body: some View {
        ZStack {
            theme.current.background.view.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                        pageView(p)
                            .tag(idx)
                            .padding(.horizontal, 32)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                actionButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Page

    @ViewBuilder
    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [p.tint, p.tint.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 160, height: 160)
                    .shadow(color: p.tint.opacity(0.4), radius: 22, y: 10)
                Image(systemName: p.icon)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .breathingPulse(amplitude: 0.03, period: 3.4)

            VStack(spacing: 14) {
                Text(p.title)
                    .font(theme.current.headingFont(.largeTitle))
                    .multilineTextAlignment(.center)
                Text(p.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Spacer(minLength: 8)
        }
    }

    // MARK: - CTA

    private var actionButton: some View {
        Button {
            if page < pages.count - 1 {
                withAnimation { page += 1 }
            } else {
                WelcomeFlow.hasCompletedWelcome = true
                onComplete()
            }
        } label: {
            Text(page < pages.count - 1 ? "Next" : "Get started")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [theme.current.tint, theme.current.tint.opacity(0.6)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flag

    /// Persisted via UserDefaults so subsequent launches skip the
    /// welcome flow. Reset by Settings → Account → "Delete account"
    /// (alongside the data wipe).
    private static let flagKey = "BudgetBot.hasCompletedWelcome"

    static var hasCompletedWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: flagKey) }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }
}
