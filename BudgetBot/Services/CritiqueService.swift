import Foundation

/// One correction the critique AI proposed against a draft from the first
/// extraction pass. Pure value type so it's trivially testable.
struct CritiqueCorrection: Codable, Hashable {
    /// 0-based index into the drafts array sent to critique.
    let draftIndex: Int
    /// Which field of the draft was wrong. The set is closed; unknown fields
    /// are ignored on apply.
    let field: String
    /// AI's new value, encoded as string. Parsed per field at apply time.
    let newValue: String
    /// Short human explanation, e.g. "Receipt shows 52.00, not 25.00 — the
    /// AI misread a 5 as a 2".
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case draftIndex = "draft_index"
        case field
        case newValue = "new_value"
        case rationale
    }
}

struct CritiqueResult: Codable {
    let corrections: [CritiqueCorrection]
}

/// Applies CritiqueCorrections to a draft array. Pure, no I/O.
enum CritiqueApplier {

    static func apply(_ corrections: [CritiqueCorrection],
                      to drafts: [ExtractedDraft]) -> [ExtractedDraft] {
        var out = drafts
        for correction in corrections {
            guard correction.draftIndex >= 0, correction.draftIndex < out.count else {
                continue
            }
            var draft = out[correction.draftIndex]
            apply(correction, to: &draft)
            out[correction.draftIndex] = draft
        }
        return out
    }

    /// Mutates a single draft.
    static func apply(_ correction: CritiqueCorrection, to draft: inout ExtractedDraft) {
        switch correction.field.lowercased() {
        case "amount":
            if let d = Decimal(string: correction.newValue.replacingOccurrences(of: ",", with: ".")) {
                draft.amount = d
            }
        case "payee":
            draft.payee = correction.newValue
        case "currency":
            draft.currency = correction.newValue.uppercased()
        case "suggested_category", "category":
            draft.suggestedCategory = correction.newValue
        case "new_category":
            draft.newCategory = correction.newValue
        case "payment_method":
            draft.paymentMethod = ExtractedDraft.PaymentMethod(rawValue: correction.newValue.lowercased())
                ?? draft.paymentMethod
        case "date":
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .iso8601)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: correction.newValue) {
                draft.date = d
            }
        case "note":
            draft.note = correction.newValue
            return  // skip the auto-append rationale so we don't double-note
        default:
            return  // unknown field; nothing to append
        }

        // Annotate the draft's note so the user sees what changed.
        let annotation = "🤖 Critique: \(correction.rationale)"
        if let existing = draft.note, !existing.isEmpty {
            draft.note = existing + "\n" + annotation
        } else {
            draft.note = annotation
        }
    }
}
