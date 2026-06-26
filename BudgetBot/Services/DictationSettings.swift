import Foundation

/// Which engine turns the user's voice into text. On-device is the
/// default — free, private, offline. The cloud options mirror what
/// gigbook's web path uses (Whisper / Gemini): more accurate on
/// accents, noise and proper nouns, but they need that provider's own
/// key, a network connection, and send audio off the device.
enum DictationEngine: String, CaseIterable, Identifiable {
    case onDevice
    case whisper
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: "On-device (Apple)"
        case .whisper:  "OpenAI Whisper"
        case .gemini:   "Google Gemini"
        }
    }

    var blurb: String {
        switch self {
        case .onDevice: "Free, private, works offline. Good accuracy."
        case .whisper:  "Most accurate on accents, noise and names. Needs an OpenAI key; audio is sent to OpenAI."
        case .gemini:   "Cloud transcription via Google. Needs a Gemini key; audio is sent to Google."
        }
    }

    var isCloud: Bool { self != .onDevice }

    /// Human name of the provider whose key this engine needs.
    var providerName: String {
        switch self {
        case .onDevice: "Apple"
        case .whisper:  "OpenAI"
        case .gemini:   "Google Gemini"
        }
    }

    /// Keychain slot for this engine's API key (nil for on-device).
    var keychainKey: KeychainKey? {
        switch self {
        case .onDevice: nil
        case .whisper:  .openAIKey
        case .gemini:   .geminiKey
        }
    }
}

/// Persisted dictation preferences. UserDefaults-backed (keys are
/// non-secret); the provider API keys live in the Keychain.
enum DictationSettings {

    private enum K {
        static let engine       = "BudgetBot.dictation.engine"
        static let language     = "BudgetBot.dictation.language"      // BCP-47, "" = device
        static let punctuation  = "BudgetBot.dictation.punctuation"
        static let offlineFallback = "BudgetBot.dictation.offlineFallback"
    }

    static var engine: DictationEngine {
        get { DictationEngine(rawValue: UserDefaults.standard.string(forKey: K.engine) ?? "") ?? .onDevice }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: K.engine) }
    }

    /// BCP-47 language for recognition; nil means follow the device.
    static var languageCode: String? {
        get {
            let v = UserDefaults.standard.string(forKey: K.language) ?? ""
            return v.isEmpty ? nil : v
        }
        set { UserDefaults.standard.set(newValue ?? "", forKey: K.language) }
    }

    /// Auto-punctuation for on-device recognition. Default on.
    static var addsPunctuation: Bool {
        get { UserDefaults.standard.object(forKey: K.punctuation) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: K.punctuation) }
    }

    /// Fall back to on-device when a cloud engine is chosen but there's
    /// no connection. Default on.
    static var offlineFallback: Bool {
        get { UserDefaults.standard.object(forKey: K.offlineFallback) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: K.offlineFallback) }
    }

    /// The engine that should actually run right now, honouring the
    /// missing-key and offline-fallback rules.
    static func effectiveEngine(isOnline: Bool) -> DictationEngine {
        let chosen = engine
        guard chosen.isCloud else { return .onDevice }
        // Cloud needs a key and a connection; otherwise fall back if allowed.
        let hasKey = (chosen.keychainKey.flatMap { KeychainService.shared.get($0) }?.isEmpty == false)
        if !hasKey { return offlineFallback ? .onDevice : chosen }
        if !isOnline { return offlineFallback ? .onDevice : chosen }
        return chosen
    }

    /// Curated language menu. `nil` value = device default.
    static let languageOptions: [(label: String, code: String?)] = [
        ("Device default", nil),
        ("English (Ireland)", "en-IE"),
        ("English (UK)", "en-GB"),
        ("English (US)", "en-US"),
        ("English (Australia)", "en-AU"),
        ("Irish (Gaeilge)", "ga-IE"),
        ("French", "fr-FR"),
        ("German", "de-DE"),
        ("Spanish", "es-ES"),
        ("Italian", "it-IT"),
        ("Portuguese (Brazil)", "pt-BR"),
        ("Polish", "pl-PL")
    ]
}
