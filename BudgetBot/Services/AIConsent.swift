import Foundation

/// Records whether the user has explicitly agreed to send their content
/// to Anthropic for AI processing.
///
/// App Review guidelines 5.1.1(i)/5.1.2(i) require affirmative consent
/// *inside the app* — disclosing what is sent and to whom — before any
/// personal data goes to a third-party AI service. A privacy-policy
/// mention alone is not sufficient. `AIConsentSheet` is the UI that
/// collects this; every AI call path checks `isGranted` before sending
/// anything.
enum AIConsent {

    static let defaultsKey = "BudgetBot.aiConsentGrantedAt"

    /// Whether the user has granted (and not since revoked) permission
    /// to send capture/Ask content to Anthropic.
    static var isGranted: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) != nil
    }

    /// When consent was granted — shown in Settings for transparency.
    static var grantedAt: Date? {
        UserDefaults.standard.object(forKey: defaultsKey) as? Date
    }

    static func grant(now: Date = .now) {
        UserDefaults.standard.set(now, forKey: defaultsKey)
    }

    static func revoke() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
