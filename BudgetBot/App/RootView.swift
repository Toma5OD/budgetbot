import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var context
    @State private var welcomeDone = WelcomeFlow.hasCompletedWelcome

    var body: some View {
        Group {
            if UITestSupport.isUITestMode {
                MainTabView()
                    .task { seedDefaultCategoriesIfNeeded(); seedUITestProfileIfNeeded() }
            } else if !welcomeDone {
                WelcomeFlow(onComplete: { welcomeDone = true })
            } else {
                switch auth.state {
                case .unknown:
                    ProgressView().controlSize(.large)
                case .signedOut:
                    SignInView()
                case .signedIn(_, _):
                    GatedRoot()
                        .task {
                            seedDefaultCategoriesIfNeeded()
                            // One-off: categorise old uncategorised rows so
                            // historical data feeds needs-vs-wants. Runs once.
                            CategoryBackfill.runOnceIfNeeded(context)
                        }
                }
            }
        }
    }

    private func seedDefaultCategoriesIfNeeded() {
        let existing = (try? context.fetch(FetchDescriptor<TxCategory>()))?.count ?? 0
        guard existing == 0 else { return }
        for (name, kind, emoji) in TxCategory.defaults {
            context.insert(TxCategory(name: name, kind: kind, emoji: emoji))
        }
        try? context.save()
    }

    private func seedUITestProfileIfNeeded() {
        let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        guard existing == nil else { return }
        let profile = UserProfile(
            appleUserID: "ui-test",
            displayName: "UI Tester",
            email: "ui@test",
            defaultCurrency: Currencies.localeDefault,
            baseCurrency: Currencies.localeDefault
        )
        context.insert(profile)
        try? context.save()
    }
}

/// Once signed in, offer API-key setup on first run — but never block
/// the app on it. The key is optional: AI features prompt for it when
/// used, and everything else works without one. Forcing a third-party
/// key to use the app at all is an App Review 2.1 risk and bad UX.
private struct GatedRoot: View {
    private static let skippedKey = "BudgetBot.apiKeyPromptSkipped"

    @State private var hasKey = KeychainService.shared.get(.anthropicAPIKey)?.isEmpty == false
    @State private var skipped = UserDefaults.standard.bool(forKey: GatedRoot.skippedKey)

    var body: some View {
        if hasKey || skipped {
            MainTabView()
        } else {
            APIKeySetupView(
                onSaved: { hasKey = true },
                onSkip: {
                    UserDefaults.standard.set(true, forKey: GatedRoot.skippedKey)
                    skipped = true
                }
            )
        }
    }
}
