import Foundation
import SwiftData

/// A batch of attachments the user queued for AI extraction. Persisted so the
/// queue survives backgrounding / restart. State machine:
///
///     queued ──▶ processing ──▶ awaitingReview ──▶ committed
///                          │
///                          ╰──▶ failed
///
/// In YOLO mode `awaitingReview` is skipped and the service moves straight
/// to `committed`.
@Model
final class CaptureJob {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var statusRaw: String = Status.queued.rawValue

    /// Captured context — frozen at queue time so the service can run without
    /// re-reading the user profile.
    var defaultAccountID: UUID?
    var aiModel: String = AIService.defaultModel
    var defaultCurrency: String = "EUR"
    var baseCurrency: String = "EUR"
    var yoloMode: Bool = false
    var critiqueMode: Bool = false

    /// Free-form text the user attached.
    var textNote: String?

    /// AI output: an array of ExtractedDraft encoded as JSON. We use JSON
    /// instead of a separate `ExtractedDraftRow` model because drafts are
    /// transient and we don't query them.
    var draftsJSON: String?

    /// Diagnostic.
    var errorMessage: String?
    var startedAt: Date?
    var completedAt: Date?

    /// Image/PDF inputs. Attachments referencing this job survive even after
    /// commit, where they are reassigned to the produced Transactions.
    @Relationship(deleteRule: .cascade, inverse: \Attachment.captureJob)
    var inputs: [Attachment]?

    init(
        id: UUID = UUID(),
        defaultAccountID: UUID? = nil,
        aiModel: String = AIService.defaultModel,
        defaultCurrency: String = "EUR",
        baseCurrency: String = "EUR",
        yoloMode: Bool = false,
        critiqueMode: Bool = false,
        textNote: String? = nil
    ) {
        self.id = id
        self.defaultAccountID = defaultAccountID
        self.aiModel = aiModel
        self.defaultCurrency = defaultCurrency
        self.baseCurrency = baseCurrency
        self.yoloMode = yoloMode
        self.critiqueMode = critiqueMode
        self.textNote = textNote
    }

    enum Status: String, Codable, CaseIterable {
        case queued, processing, awaitingReview, committed, failed
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var drafts: [ExtractedDraft] {
        get {
            guard let raw = draftsJSON, let data = raw.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ExtractedDraft].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                draftsJSON = String(data: data, encoding: .utf8)
            }
        }
    }
}
