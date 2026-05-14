import Foundation
import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
final class CaptureViewModel {
    var images: [UIImage] = []
    var pdfs: [(Data, String)] = []
    var textNote: String = ""
    var defaultCurrency: String = "EUR"
    var baseCurrency: String = "EUR"
    var aiModel: String = AIService.defaultModel
    var yoloMode: Bool = false
    var defaultAccountID: UUID?
    var lastError: String?

    var hasInput: Bool {
        !images.isEmpty || !pdfs.isEmpty || !textNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var attachmentCount: Int {
        images.count + pdfs.count + (textNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    func reset() {
        images.removeAll()
        pdfs.removeAll()
        textNote = ""
        lastError = nil
    }

    // MARK: - Share-extension intake

    func ingestPending() {
        for item in PendingCaptureStore.pending() {
            switch item.kind {
            case .image:
                if let data = PendingCaptureStore.loadBinary(item), let img = UIImage(data: data) {
                    images.append(img)
                }
            case .pdf:
                if let data = PendingCaptureStore.loadBinary(item) {
                    pdfs.append((data, item.filename ?? "shared.pdf"))
                }
            case .text:
                if let t = item.text {
                    textNote += textNote.isEmpty ? t : "\n\n\(t)"
                }
            }
            PendingCaptureStore.remove(item.id)
        }
    }

    // MARK: - Queue for background processing

    /// Persists the current inputs as a `CaptureJob` row and clears the
    /// in-memory state. The queue service picks up the job and processes it
    /// in the background — either auto-committing (YOLO) or queuing for the
    /// user to review.
    func queueForProcessing(in context: ModelContext, pump: () -> Void) {
        lastError = nil
        guard hasInput else { return }

        let job = CaptureJob(
            defaultAccountID: defaultAccountID,
            aiModel: aiModel,
            defaultCurrency: defaultCurrency,
            baseCurrency: baseCurrency,
            yoloMode: yoloMode,
            textNote: textNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : textNote
        )
        context.insert(job)

        for img in images {
            guard let data = img.jpegData(compressionQuality: 0.8) else { continue }
            let att = Attachment(kind: .image, data: data)
            att.captureJob = job
            context.insert(att)
        }
        for (data, name) in pdfs {
            let att = Attachment(kind: .pdf, filename: name, data: data)
            att.captureJob = job
            context.insert(att)
        }
        if !textNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let att = Attachment(kind: .text, text: textNote)
            att.captureJob = job
            context.insert(att)
        }

        do {
            try context.save()
            reset()
            pump()
        } catch {
            lastError = "Couldn't queue: \(error.localizedDescription)"
        }
    }

    // MARK: - Pure matchers (testable, used by CaptureQueueService)

    nonisolated static func matchCategory(for draft: ExtractedDraft, in categories: [TxCategory]) -> TxCategory? {
        let preferredKind: CategoryKind = draft.amount >= 0 ? .income : .expense
        guard let suggested = draft.suggestedCategory?.lowercased() else {
            return categories.first { $0.kind == preferredKind }
        }
        if let exact = categories.first(where: { $0.name.lowercased() == suggested }) {
            return exact
        }
        if let loose = categories.first(where: {
            suggested.contains($0.name.lowercased()) || $0.name.lowercased().contains(suggested)
        }) {
            return loose
        }
        return categories.first { $0.kind == preferredKind }
    }

    nonisolated static func matchAccount(for draft: ExtractedDraft, in accounts: [Account]) -> Account? {
        if let hint = draft.accountHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hint.isEmpty {
            let hintLower = hint.lowercased()
            if let exact = accounts.first(where: { $0.name.lowercased() == hintLower }) {
                return exact
            }
            if let partial = accounts.first(where: {
                let n = $0.name.lowercased()
                return n.contains(hintLower) || hintLower.contains(n)
            }) {
                return partial
            }
        }
        switch draft.paymentMethod {
        case .cash:
            if let cash = accounts.first(where: { $0.kind == .cash }) { return cash }
        case .card:
            if let card = accounts.first(where: {
                ($0.kind == .credit || $0.kind == .bank) && $0.currency == draft.currency
            }) { return card }
        case .unknown:
            break
        }
        return nil
    }

    nonisolated static func snapshotFX(
        from: String,
        to: String,
        rates: [String: Decimal]
    ) -> (rate: Decimal?, base: String?) {
        let fromU = from.uppercased(), toU = to.uppercased()
        if fromU == toU { return (Decimal(1), toU) }
        let one = Decimal(1)
        let converted = FXService.convert(one, from: fromU, to: toU, rates: rates)
        guard converted != one || fromU == toU else { return (nil, nil) }
        return (converted, toU)
    }
}
