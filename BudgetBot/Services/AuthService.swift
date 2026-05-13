import Foundation
import AuthenticationServices
import SwiftData

@Observable
@MainActor
final class AuthService: NSObject {
    enum State {
        case unknown
        case signedOut
        case signedIn(userID: String, provider: Provider)
    }

    enum Provider: String { case apple, google }

    var state: State = .unknown
    /// Last sign-in / revoke error surfaced for the UI.
    var lastError: String?

    /// The Notification token isn't actor-isolated so `deinit` (which is
    /// implicitly nonisolated) can clean it up.
    private nonisolated(unsafe) var revokeObserver: NSObjectProtocol?

    func bootstrap() {
        // Listen for system-level revocation (user toggled BudgetBot off in
        // iCloud Settings → Sign in with Apple).
        if revokeObserver == nil {
            revokeObserver = NotificationCenter.default.addObserver(
                forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.signOut() }
            }
        }

        if let id = KeychainService.shared.get(.appleUserID) {
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: id) { [weak self] credState, _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch credState {
                    case .authorized:
                        self.state = .signedIn(userID: id, provider: .apple)
                    case .revoked, .notFound, .transferred:
                        KeychainService.shared.delete(.appleUserID)
                        self.state = .signedOut
                    @unknown default:
                        self.state = .signedOut
                    }
                }
            }
        } else if let id = KeychainService.shared.get(.googleUserID) {
            // Google has no in-process credential-state check; trust the
            // Keychain entry until the user explicitly signs out.
            state = .signedIn(userID: id, provider: .google)
        } else {
            state = .signedOut
        }
    }

    /// Handle the Google OAuth flow, upserting a UserProfile keyed on the
    /// Google `sub` (stable Google user ID).
    func signInWithGoogle(context: ModelContext) async {
        lastError = nil
        do {
            let profile = try await GoogleAuthService().signIn()
            try? KeychainService.shared.set(profile.sub, for: .googleUserID)

            // `#Predicate` can't capture struct property accesses, only locals.
            let sub = profile.sub
            let descriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate { $0.appleUserID == sub }
            )
            let existing = (try? context.fetch(descriptor))?.first
            if let p = existing {
                if let e = profile.email { p.email = e }
                if let n = profile.name  { p.displayName = n }
                p.authProvider = Provider.google.rawValue
            } else {
                let p = UserProfile(
                    appleUserID: profile.sub,
                    displayName: profile.name,
                    email: profile.email,
                    defaultCurrency: Currencies.localeDefault,
                    baseCurrency: Currencies.localeDefault,
                    authProvider: Provider.google.rawValue
                )
                context.insert(p)
            }
            try? context.save()
            state = .signedIn(userID: profile.sub, provider: .google)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func handle(_ result: Result<ASAuthorization, Error>, context: ModelContext) {
        switch result {
        case .failure(let err):
            lastError = err.localizedDescription
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let userID = cred.user
            try? KeychainService.shared.set(userID, for: .appleUserID)

            let descriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate { $0.appleUserID == userID }
            )
            let existing = (try? context.fetch(descriptor))?.first
            if let profile = existing {
                if profile.email == nil, let e = cred.email { profile.email = e }
                if profile.displayName == nil, let n = cred.fullName {
                    profile.displayName = PersonNameComponentsFormatter().string(from: n)
                }
            } else {
                let nameStr = cred.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
                let localeCurrency = Currencies.localeDefault
                let profile = UserProfile(
                    appleUserID: userID,
                    displayName: nameStr,
                    email: cred.email,
                    defaultCurrency: localeCurrency,
                    baseCurrency: localeCurrency,
                    authProvider: Provider.apple.rawValue
                )
                context.insert(profile)
            }
            try? context.save()
            lastError = nil
            state = .signedIn(userID: userID, provider: .apple)
        }
    }

    func signOut() {
        KeychainService.shared.delete(.appleUserID)
        KeychainService.shared.delete(.googleUserID)
        state = .signedOut
    }

    deinit {
        if let obs = revokeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
