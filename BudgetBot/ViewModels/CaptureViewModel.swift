import Foundation
import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
final class CaptureViewModel {
    enum Stage {
        case idle
        case extracting
        case review(drafts: [ExtractedDraft], duplicates: [UUID: [UUID]])
        case error(String)
    }

    var stage: Stage = .idle
    var images: [UIImage] = []
    var pdfs: [(Data, String)] = []
    var textNote: String = ""
    var defaultCurrency: String = "EUR"
    var aiModel: String = AIService.defaultModel

    private var inflight: Task<Void, Never>?

    var hasInput: Bool {
        !images.isEmpty || !pdfs.isEmpty || !textNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reset() {
        inflight?.cancel()
        inflight = nil
        stage = .idle
        images.removeAll()
        pdfs.removeAll()
        textNote = ""
    }

    func cancel() {
        inflight?.cancel()
        inflight = nil
        if case .extracting = stage { stage = .idle }
    }

    // MARK: - Pending intake from Share Extension

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

    // MARK: - Extract

    func extract(accounts: [Account], existing: [Transaction]) async {
        var inputs: [AIService.Input] = []
        for img in images { inputs.append(.image(img)) }
        for (data, name) in pdfs { inputs.append(.pdf(data, filename: name)) }
        let trimmed = textNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { inputs.append(.text(trimmed)) }
        guard !inputs.isEmpty else { return }

        guard let service = AIService.fromKeychain(model: aiModel) else {
            stage = .error("No AI API key set. Add one in Settings.")
            return
        }
        stage = .extracting

        let accountContexts: [AccountContext] = accounts.map {
            AccountContext(name: $0.name, kind: $0.kind.rawValue, currency: $0.currency)
        }
        let dupSnapshot = existing.map {
            DuplicateDetector.Existing(id: $0.id, date: $0.date, amount: $0.amount, payee: $0.payee)
        }
        let captured = inputs
        let currency = defaultCurrency

        let task = Task<Void, Never> { [weak self] in
            do {
                let drafts = try await service.extract(
                    from: captured,
                    defaultCurrency: currency,
                    accounts: accountContexts
                )
                guard !Task.isCancelled else { return }
                let detector = DuplicateDetector()
                var dupes: [UUID: [UUID]] = [:]
                for d in drafts {
                    let hits = detector.duplicates(for: d, against: dupSnapshot)
                    if !hits.isEmpty { dupes[d.id] = hits }
                }
                await MainActor.run {
                    self?.stage = drafts.isEmpty
                        ? .error("AI couldn't find any transactions in that.")
                        : .review(drafts: drafts, duplicates: dupes)
                }
            } catch {
                await MainActor.run {
                    if case AIService.AIError.cancelled = error { return }
                    self?.stage = .error(error.localizedDescription)
                }
            }
        }
        inflight = task
        await task.value
    }

    // MARK: - Commit

    /// Persist confirmed drafts as Transactions, splitting into `Split` rows
    /// when the AI returned per-item categories that disagree with the
    /// headline. FX is snapshotted at commit time.
    func commit(
        drafts: [ExtractedDraft],
        defaultAccount: Account,
        accounts: [Account],
        categories: [TxCategory],
        baseCurrency: String,
        fxRates: [String: Decimal],
        in context: ModelContext
    ) {
        for (idx, draft) in drafts.enumerated() {
            let headlineCategory = Self.matchCategory(for: draft, in: categories)
            let acc = Self.matchAccount(for: draft, in: accounts) ?? defaultAccount

            let attachment: Attachment?
            if idx == 0, let img = images.first, let jpeg = img.jpegData(compressionQuality: 0.7) {
                attachment = Attachment(kind: .image, data: jpeg)
            } else if idx == 0, let (data, name) = pdfs.first {
                attachment = Attachment(kind: .pdf, filename: name, data: data)
            } else if idx == 0, !textNote.isEmpty {
                attachment = Attachment(kind: .text, text: textNote)
            } else {
                attachment = nil
            }

            let (snapRate, snapBase) = Self.snapshotFX(
                from: draft.currency,
                to: baseCurrency,
                rates: fxRates
            )
            let payment = Transaction.PaymentMethod(rawValue: draft.paymentMethod.rawValue) ?? .unknown

            let tx = Transaction(
                date: draft.date,
                amount: draft.amount,
                currency: draft.currency,
                payee: draft.payee,
                note: draft.note,
                confirmed: true,
                aiExtracted: true,
                paymentMethod: payment,
                fxRateToBase: snapRate,
                fxBaseCurrency: snapBase,
                account: acc,
                category: headlineCategory,
                attachment: attachment
            )
            context.insert(tx)

            // Only persist line items as Splits if the AI captured per-item
            // categories that meaningfully disagree with the headline.
            // Otherwise this is a single-category transaction and the
            // line-items are just decoration on the receipt.
            let lineCategoryNames = Set(draft.lineItems.compactMap { $0.category?.lowercased() })
            let headlineName = headlineCategory?.name.lowercased()
            let isMulticat = lineCategoryNames.count > 1
                || (lineCategoryNames.count == 1 && lineCategoryNames.first != headlineName)

            if isMulticat && !draft.lineItems.isEmpty {
                for li in draft.lineItems {
                    let cat = li.category.flatMap { name in
                        categories.first { $0.name.lowercased() == name.lowercased() }
                    } ?? headlineCategory
                    let signed = draft.amount < 0 ? -abs(li.amount) : abs(li.amount)
                    let split = Split(
                        description: li.description,
                        amount: signed,
                        category: cat,
                        transaction: tx
                    )
                    context.insert(split)
                }
                // Clear headline category so aggregation always uses splits.
                tx.category = nil
            }
        }
        try? context.save()
        reset()
    }

    // MARK: - Pure matchers (testable)

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
        // 1. Explicit account hint wins.
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
        // 2. Payment-method hint.
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

    /// Given `from`/`to` currency codes and a rate map, returns the rate
    /// 1×from→to. `nil` when unknown.
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
