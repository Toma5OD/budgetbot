import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Thin wrapper around Apple's on-device Foundation Models framework
/// (iOS 26+). When available *and* the user has opted in via
/// `isPreferred`, callers can route text-only generations through this
/// instead of the cloud (Anthropic) — the device never leaves the
/// user's phone.
///
/// Today this powers:
///   - AI recommendations on the Analytics page (short text-out)
///   - Anything else that's pure text-in / text-out and doesn't need
///     the full tool-use loop
///
/// What it deliberately does NOT do yet:
///   - Receipt photo extraction. Apple FM is text-only; doing receipts
///     on-device would need Vision OCR first, then FM, then structured
///     output via `@Generable`. Worth it eventually; out of scope now.
///   - The Ask-tab conversational loop. The Anthropic path uses
///     `query_transactions` tool-use which has no clean equivalent
///     here without a rewrite.
///
/// Behaviour matrix:
///
/// | iOS  | Apple Intelligence | toggle | result          |
/// | --- | --- | --- | --- |
/// | <26  | n/a                | any    | unavailable     |
/// | 26+  | off / unsupported  | any    | unavailable     |
/// | 26+  | available          | off    | unavailable     |
/// | 26+  | available          | on     | uses on-device  |
@MainActor
final class LocalLLMService {

    static let shared = LocalLLMService()
    private init() {}

    // MARK: - Preference

    private let preferKey = "BudgetBot.preferOnDeviceAI"

    /// User opt-in. Defaults to false because most users either lack
    /// the hardware (pre-A17 Pro), have Apple Intelligence disabled,
    /// or run iOS < 26.
    var isPreferred: Bool {
        get { UserDefaults.standard.bool(forKey: preferKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferKey) }
    }

    // MARK: - Availability

    /// True only when the framework is linked, the OS is iOS 26+,
    /// Apple Intelligence is enabled, and the device supports it.
    /// Use this BEFORE attempting `generate(_:)` — the call will throw
    /// otherwise.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default:         return false
            }
        }
        #endif
        return false
    }

    /// Granular availability — useful for the Settings row's subtitle so
    /// we can tell the user *why* it's off ("Turn on Apple Intelligence
    /// in iOS Settings to use this.").
    var availabilityReason: AvailabilityReason {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:                              return .available
            case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceDisabled
            case .unavailable(.deviceNotEligible):        return .deviceNotEligible
            case .unavailable(.modelNotReady):            return .modelDownloading
            case .unavailable(let other):                 return .other(String(describing: other))
            @unknown default:                             return .other("unknown availability")
            }
        }
        #endif
        return .iosTooOld
    }

    enum AvailabilityReason {
        case available
        case iosTooOld
        case deviceNotEligible
        case appleIntelligenceDisabled
        case modelDownloading
        case other(String)

        var userFacingMessage: String {
            switch self {
            case .available:                  return "Ready on-device."
            case .iosTooOld:                  return "Needs iOS 26 or newer."
            case .deviceNotEligible:          return "This device doesn't support Apple Intelligence."
            case .appleIntelligenceDisabled:  return "Turn on Apple Intelligence in iOS Settings to use this."
            case .modelDownloading:           return "Apple Intelligence is downloading — try again soon."
            case .other(let s):               return "Unavailable: \(s)"
            }
        }
    }

    // MARK: - Generation

    /// Generates a text response on-device. Throws if unavailable so
    /// callers can fall back to a cloud path.
    func generate(_ prompt: String,
                  instructions: String? = nil) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard isAvailable else { throw LocalLLMError.unavailable(availabilityReason) }
            let session: LanguageModelSession
            if let instructions {
                session = LanguageModelSession(instructions: Instructions(instructions))
            } else {
                session = LanguageModelSession()
            }
            let resp = try await session.respond(to: prompt)
            return resp.content
        }
        #endif
        throw LocalLLMError.unavailable(.iosTooOld)
    }
}

enum LocalLLMError: LocalizedError {
    case unavailable(LocalLLMService.AvailabilityReason)

    var errorDescription: String? {
        switch self {
        case .unavailable(let r): return r.userFacingMessage
        }
    }
}
