import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if UITestSupport.isUITestMode {
                MainTabView()
                    .task { seedDefaultCategoriesIfNeeded(); seedUITestProfileIfNeeded() }
            } else {
                switch auth.state {
                case .unknown:
                    ProgressView().controlSize(.large)
                case .signedOut:
                    SignInView()
                case .signedIn:
                    GatedRoot()
                        .task { seedDefaultCategoriesIfNeeded() }
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
            defaultCurrency: "USD",
            baseCurrency: "USD"
        )
        context.insert(profile)
        try? context.save()
    }
}

/// Once signed in, gate the main UI on having an API key.
private struct GatedRoot: View {
    @State private var hasKey = KeychainService.shared.get(.anthropicAPIKey)?.isEmpty == false

    var body: some View {
        if hasKey {
            MainTabView()
        } else {
            APIKeySetupView(onSaved: { hasKey = true })
        }
    }
}
