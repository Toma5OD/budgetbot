import Foundation
import SwiftData
import UIKit

/// Watches SwiftData for queued `CaptureJob` rows, sends each to the AI in
/// turn, and routes the result based on the job's `yoloMode`:
///
/// - YOLO on:  drafts get committed straight to Transactions and the job
///             is marked `.committed`. The user never has to touch a thing.
/// - YOLO off: drafts are stored on the job, status becomes
///             `.awaitingReview`, and the notification centre surfaces it.
///
/// The service is single-flight (one job at a time) so the user's API key
/// usage stays predictable.
@MainActor
@Observable
final class CaptureQueueService {

    /// Public state the UI can read for the inline "N processing" pill.
    private(set) var processingCount: Int = 0
    private(set) var awaitingReviewCount: Int = 0
    private(set) var queuedCount: Int = 0

    private let container: ModelContainer
    private var fx: FXService?
    private var inflight: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
    }

    func wire(fx: FXService) {
        self.fx = fx
    }

    // MARK: - Public

    /// Pump the queue. Idempotent; the service will only run one job at a
    /// time even if poked repeatedly.
    func pump() {
        refreshCounts()
        guard inflight == nil else { return }
        inflight = Task { [weak self] in
            await self?.drain()
            self?.inflight = nil
        }
    }

    /// Mark a job's drafts as committed by the user (called after Review UI
    /// writes Transactions). The service moves attachments off the job and
    /// clears its draft cache.
    func markCommitted(_ job: CaptureJob) {
        job.status = .committed
        job.completedAt = .now
        job.draftsJSON = nil
        try? container.mainContext.save()
        refreshCounts()
    }

    /// User dismissed the awaiting-review job without saving anything.
    func dismiss(_ job: CaptureJob) {
        let ctx = container.mainContext
        ctx.delete(job)
        try? ctx.save()
        refreshCounts()
    }

    // MARK: - Internals

    private func drain() async {
        while let job = nextQueued() {
            await process(job)
        }
        refreshCounts()
    }

    private func nextQueued() -> CaptureJob? {
        let ctx = container.mainContext
        let descriptor = FetchDescriptor<CaptureJob>(
            predicate: #Predicate { $0.statusRaw == "queued" },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? ctx.fetch(descriptor))?.first
    }

    private func process(_ job: CaptureJob) async {
        let ctx = container.mainContext
        job.status = .processing
        job.startedAt = .now
        try? ctx.save()
        refreshCounts()

        // Build AI inputs from the job's persisted attachments.
        var inputs: [AIService.Input] = []
        for att in (job.inputs ?? []) {
            switch att.kind {
            case .image:
                if let data = att.data, let img = UIImage(data: data) {
                    inputs.append(.image(img))
                }
            case .pdf:
                if let data = att.data {
                    inputs.append(.pdf(data, filename: att.filename))
                }
            case .text:
                if let t = att.text, !t.isEmpty { inputs.append(.text(t)) }
            }
        }
        if let note = job.textNote, !note.isEmpty {
            inputs.append(.text(note))
        }

        guard !inputs.isEmpty else {
            job.status = .failed
            job.errorMessage = "Nothing to send to the AI"
            job.completedAt = .now
            try? ctx.save()
            return
        }

        // Surface accounts so the AI can hint payment routing.
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate<Account> { !$0.archived }
        ))) ?? []
        let accountContexts = accounts.map {
            AccountContext(name: $0.name, kind: $0.kind.rawValue, currency: $0.currency)
        }

        guard let service = AIService.fromKeychain(model: job.aiModel) else {
            job.status = .failed
            job.errorMessage = "No AI API key configured"
            job.completedAt = .now
            try? ctx.save()
            return
        }

        do {
            let drafts = try await service.extract(
                from: inputs,
                defaultCurrency: job.defaultCurrency,
                accounts: accountContexts
            )
            if drafts.isEmpty {
                job.status = .failed
                job.errorMessage = "AI didn't find any transactions"
                job.completedAt = .now
                try? ctx.save()
                return
            }
            job.drafts = drafts

            if job.yoloMode {
                commitDrafts(job: job, drafts: drafts, accounts: accounts)
                job.status = .committed
                job.draftsJSON = nil
            } else {
                job.status = .awaitingReview
            }
            job.completedAt = .now
            try? ctx.save()
        } catch {
            job.status = .failed
            job.errorMessage = error.localizedDescription
            job.completedAt = .now
            try? ctx.save()
        }
    }

    private func commitDrafts(job: CaptureJob, drafts: [ExtractedDraft], accounts: [Account]) {
        let ctx = container.mainContext
        var categories = (try? ctx.fetch(FetchDescriptor<TxCategory>())) ?? []
        let existingPayees = ((try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []).map(\.payee)
        var resolvedAccounts = accounts
        var defaultAccount = resolvedAccounts.first { $0.id == job.defaultAccountID } ?? resolvedAccounts.first

        if defaultAccount == nil {
            let wallet = Account(
                name: "Wallet",
                kind: .cash,
                currency: job.defaultCurrency,
                openingBalance: 0
            )
            ctx.insert(wallet)
            resolvedAccounts.append(wallet)
            defaultAccount = wallet
        }

        let fxRates = fx?.rates ?? [:]
        let firstInput = (job.inputs ?? []).first

        for (idx, draft) in drafts.enumerated() {
            // Resolve category — fuzzy match existing, OR create new from AI's
            // proposal if no match. Returns nil only when AI gave nothing.
            let cat = CaptureCategoryResolver.resolve(
                draft: draft,
                in: &categories,
                context: ctx
            )
            let acc = CaptureViewModel.matchAccount(for: draft, in: resolvedAccounts) ?? defaultAccount

            // Canonicalise the merchant name so duplicates collapse.
            let canonicalPayee = PayeeNormaliser.canonical(
                forKey: PayeeNormaliser.key(draft.payee),
                in: existingPayees,
                fallback: draft.payee
            )

            let (snapRate, snapBase) = CaptureViewModel.snapshotFX(
                from: draft.currency,
                to: job.baseCurrency,
                rates: fxRates
            )

            let payment = Transaction.PaymentMethod(rawValue: draft.paymentMethod.rawValue) ?? .unknown
            let tx = Transaction(
                date: draft.date,
                amount: draft.amount,
                currency: draft.currency,
                payee: canonicalPayee,
                note: draft.note,
                confirmed: true,
                aiExtracted: true,
                paymentMethod: payment,
                fxRateToBase: snapRate,
                fxBaseCurrency: snapBase,
                account: acc,
                category: cat,
                attachment: idx == 0 ? firstInput : nil,
                createdAt: .now
            )
            ctx.insert(tx)

            // Multi-category split: only when AI tagged items with categories
            // that actually disagree with the headline.
            let liCats = Set(draft.lineItems.compactMap { $0.category?.lowercased() })
            let headlineName = cat?.name.lowercased()
            let isMulticat = liCats.count > 1
                || (liCats.count == 1 && liCats.first != headlineName)

            if isMulticat && !draft.lineItems.isEmpty {
                for li in draft.lineItems {
                    // Splits inherit the headline category when the AI left
                    // their per-item category blank — fixes the "Uncategorised"
                    // bug we saw on the Chemist Warehouse receipts.
                    let liCat: TxCategory? = {
                        if let name = li.category {
                            return categories.first { $0.name.lowercased() == name.lowercased() }
                        }
                        return cat
                    }()
                    let signed = draft.amount < 0 ? -abs(li.amount) : abs(li.amount)
                    let split = Split(
                        description: li.description,
                        amount: signed,
                        category: liCat,
                        transaction: tx
                    )
                    ctx.insert(split)
                }
                tx.category = nil
            }
        }
        if let firstInput {
            firstInput.captureJob = nil
        }
    }

    private func refreshCounts() {
        let ctx = container.mainContext
        queuedCount = countWhere(status: "queued", in: ctx)
        processingCount = countWhere(status: "processing", in: ctx)
        awaitingReviewCount = countWhere(status: "awaitingReview", in: ctx)
    }

    private func countWhere(status: String, in ctx: ModelContext) -> Int {
        let descriptor = FetchDescriptor<CaptureJob>(
            predicate: #Predicate { $0.statusRaw == status }
        )
        return (try? ctx.fetchCount(descriptor)) ?? 0
    }
}
