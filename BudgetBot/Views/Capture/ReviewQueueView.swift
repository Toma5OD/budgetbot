import SwiftUI
import SwiftData

/// Walks awaiting-review CaptureJobs sequentially, draft-by-draft, in a
/// card-based reviewer. The user can edit the payee/amount/category, then
/// accept (commit as Transaction) or skip. When all drafts in a job are
/// processed the job is marked .committed; the next awaiting job is loaded
/// automatically. Closes itself when the queue is empty.
struct ReviewQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme
    @Environment(CaptureQueueService.self) private var queue

    @Query(filter: #Predicate<CaptureJob> { $0.statusRaw == "awaitingReview" },
           sort: \CaptureJob.createdAt, order: .forward)
    private var jobs: [CaptureJob]
    @Query(filter: #Predicate<Account> { !$0.archived }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query private var categories: [TxCategory]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var draftIndex = 0
    @State private var editingDraft: ExtractedDraft?
    @State private var selectedAccountID: UUID?
    @State private var commitError: String?
    @State private var rescanHint: String = ""
    @State private var showRescanSheet = false
    @State private var isRescanning = false
    @State private var rescanError: String?

    private var currentJob: CaptureJob? { jobs.first }
    private var currentDrafts: [ExtractedDraft] { currentJob?.drafts ?? [] }
    private var currentDraft: ExtractedDraft? {
        guard draftIndex < currentDrafts.count else { return nil }
        return currentDrafts[draftIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.current.background.view

                if let _ = currentJob, let draft = currentDraft {
                    DraftReviewCard(
                        draft: editingDraft ?? draft,
                        accounts: accounts,
                        selectedAccountID: $selectedAccountID,
                        isRescanning: isRescanning,
                        onAccept: { acceptCurrent() },
                        onSkip:   { skipCurrent() },
                        onEdit:   { editingDraft = draft },
                        onRescan: { showRescanSheet = true },
                        progress: jobProgress
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                } else {
                    emptyState
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if let job = currentJob {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Skip the rest of this batch", role: .destructive) {
                                skipRestOfJob(job)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .onAppear { hydrate() }
            .alert("Couldn't save", isPresented: Binding(
                get: { commitError != nil },
                set: { if !$0 { commitError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(commitError ?? "")
            }
            .sheet(item: $editingDraft) { _ in
                if let editing = editingDraft {
                    EditDraftSheet(
                        draft: Binding(
                            get: { editingDraft ?? editing },
                            set: { editingDraft = $0 }
                        ),
                        categories: categories,
                        accounts: accounts,
                        selectedAccountID: $selectedAccountID
                    )
                }
            }
            .sheet(isPresented: $showRescanSheet) {
                RescanSheet(
                    hint: $rescanHint,
                    isRunning: $isRescanning,
                    error: $rescanError
                ) {
                    Task { await rescanCurrent() }
                }
            }
        }
    }

    // MARK: - Header

    private var navTitle: String {
        guard !jobs.isEmpty else { return "Caught up" }
        let total = currentDrafts.count
        let idx = min(draftIndex + 1, total)
        return "\(idx) of \(total)"
    }

    private var jobProgress: (Int, Int) {
        guard !currentDrafts.isEmpty else { return (0, 0) }
        return (min(draftIndex + 1, currentDrafts.count), currentDrafts.count)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("You're caught up").font(.title3.bold())
            Text("Nothing else needs your eyes. We'll surface the next batch here when the AI is done with it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func hydrate() {
        if selectedAccountID == nil {
            selectedAccountID = currentJob?.defaultAccountID ?? accounts.first?.id
        }
    }

    private func acceptCurrent() {
        guard let job = currentJob, let draft = (editingDraft ?? currentDraft) else { return }
        do {
            try commit(draft: draft, in: job)
            advance(job: job)
        } catch {
            // Keep the user on the current draft so they can try again.
            commitError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func skipCurrent() {
        guard let job = currentJob else { return }
        advance(job: job)
    }

    private func advance(job: CaptureJob) {
        editingDraft = nil
        if draftIndex + 1 >= currentDrafts.count {
            // Finished this job.
            queue.markCommitted(job)
            draftIndex = 0
            selectedAccountID = jobs.dropFirst().first?.defaultAccountID ?? accounts.first?.id
        } else {
            draftIndex += 1
        }
    }

    private func skipRestOfJob(_ job: CaptureJob) {
        queue.markCommitted(job)
        draftIndex = 0
        editingDraft = nil
    }

    /// Re-run extraction on this draft with the user's hint as extra context.
    /// Replaces the current draft in place when the AI returns.
    private func rescanCurrent() async {
        guard let job = currentJob, draftIndex < currentDrafts.count else { return }
        let originalDraft = currentDrafts[draftIndex]
        let hint = rescanHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hint.isEmpty else { return }

        isRescanning = true
        rescanError = nil
        defer { isRescanning = false }

        guard let service = AIService.fromKeychain(model: job.aiModel) else {
            rescanError = "No AI API key set."
            return
        }

        // Reconstruct AIService.Input from the job's attachments.
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
                if let t = att.text { inputs.append(.text(t)) }
            }
        }
        if let note = job.textNote, !note.isEmpty { inputs.append(.text(note)) }

        do {
            let refined = try await service.refineDraft(
                originalDraft,
                userHint: hint,
                inputs: inputs,
                defaultCurrency: job.defaultCurrency
            )
            // Swap the draft in the job's persisted list.
            var drafts = job.drafts
            if draftIndex < drafts.count {
                drafts[draftIndex] = refined
                job.drafts = drafts
                try? context.save()
            }
            editingDraft = nil
            showRescanSheet = false
            rescanHint = ""
        } catch {
            rescanError = error.localizedDescription
        }
    }

    private func commit(draft: ExtractedDraft, in job: CaptureJob) throws {
        // Pick the user's selected account; fall back to AI-matched then first
        // available. If the user has *no* accounts yet, auto-create a
        // sensible "Wallet" cash account so the transaction has somewhere to
        // land. (Transaction.account is optional, but a nil-account row never
        // shows up under any Account, which surprises the user.)
        let acc = accounts.first { $0.id == selectedAccountID }
            ?? CaptureViewModel.matchAccount(for: draft, in: accounts)
            ?? accounts.first
            ?? autoCreateDefaultAccount(profileCurrency: job.defaultCurrency)

        var workingCategories = categories
        let cat = CaptureCategoryResolver.resolve(
            draft: draft,
            in: &workingCategories,
            context: context
        )

        // Canonical merchant spelling, so duplicates collapse in analytics.
        let allTxs = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let canonicalPayee = PayeeNormaliser.canonical(
            forKey: PayeeNormaliser.key(draft.payee),
            in: allTxs.map(\.payee),
            fallback: draft.payee
        )

        let (snapRate, snapBase) = CaptureViewModel.snapshotFX(
            from: draft.currency,
            to: job.baseCurrency,
            rates: fx.rates
        )
        let payment = Transaction.PaymentMethod(rawValue: draft.paymentMethod.rawValue) ?? .unknown

        let attachmentToUse: Attachment? = {
            if draftIndex == 0 { return (job.inputs ?? []).first }
            return nil
        }()
        if let att = attachmentToUse { att.captureJob = nil }

        let tx = Transaction(
            date: draft.date,
            amount: draft.amount,
            currency: draft.currency,
            payee: canonicalPayee,
            note: draft.note,
            confirmed: true,
            aiExtracted: true,
            paymentMethod: payment,
            cardBrand: draft.cardBrand,
            cardLast4: draft.cardLast4,
            fxRateToBase: snapRate,
            fxBaseCurrency: snapBase,
            account: acc,
            category: cat,
            attachment: attachmentToUse,
            createdAt: .now
        )
        context.insert(tx)

        // Splits when AI produced multi-category line items
        let lineCategoryNames = Set(draft.lineItems.compactMap { $0.category?.lowercased() })
        let headlineName = cat?.name.lowercased()
        let isMulticat = lineCategoryNames.count > 1
            || (lineCategoryNames.count == 1 && lineCategoryNames.first != headlineName)

        if isMulticat && !draft.lineItems.isEmpty {
            for li in draft.lineItems {
                // Inherit headline category when AI left this item blank.
                let liCat: TxCategory? = {
                    if let name = li.category {
                        return workingCategories.first { $0.name.lowercased() == name.lowercased() }
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
                context.insert(split)
            }
            tx.category = nil
        }

        try context.save()
    }

    /// Last-resort: the user accepted a transaction but has no accounts at
    /// all yet. Spin up a "Wallet" cash account so they don't lose the row.
    private func autoCreateDefaultAccount(profileCurrency: String) -> Account {
        let acc = Account(
            name: "Wallet",
            kind: .cash,
            currency: profileCurrency,
            openingBalance: 0
        )
        context.insert(acc)
        return acc
    }
}

// MARK: - Card

private struct DraftReviewCard: View {
    let draft: ExtractedDraft
    let accounts: [Account]
    @Binding var selectedAccountID: UUID?
    let isRescanning: Bool
    let onAccept: () -> Void
    let onSkip:   () -> Void
    let onEdit:   () -> Void
    let onRescan: () -> Void
    let progress: (Int, Int)

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 18) {
            ProgressView(value: progressFraction)
                .tint(theme.current.tint)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(draft.payee)
                        .font(theme.current.headingFont(.title2))
                    Spacer()
                    ConfidencePill(value: draft.confidence)
                }

                Text(CurrencyFormatter.string(for: draft.amount, currency: draft.currency))
                    .font(.system(size: 44, weight: .bold, design: theme.current.numericDesign))
                    .foregroundStyle(draft.amount < 0 ? theme.current.expenseColor : theme.current.incomeColor)

                HStack(spacing: 10) {
                    if let cat = draft.suggestedCategory {
                        Label(cat, systemImage: "tag.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.current.tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(theme.current.tint)
                    }
                    if draft.paymentMethod != .unknown {
                        Label(draft.paymentMethod == .cash ? "Cash" : "Card",
                              systemImage: draft.paymentMethod == .cash ? "banknote.fill" : "creditcard.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(draft.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !draft.lineItems.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Line items")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(draft.lineItems) { item in
                            HStack {
                                Text(item.description).font(.caption)
                                if let cat = item.category {
                                    Text("· \(cat)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(CurrencyFormatter.string(for: item.amount, currency: draft.currency))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !accounts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save to")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Picker("Account", selection: $selectedAccountID) {
                            ForEach(accounts) { a in
                                Label(a.name, systemImage: a.kind.systemImage)
                                    .tag(Optional(a.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()

            Spacer()

            HStack(spacing: 12) {
                Button(role: .destructive, action: onSkip) {
                    Label("Skip", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isRescanning)

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isRescanning)

                Button(action: onAccept) {
                    Label("Accept", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRescanning)
            }

            Button(action: onRescan) {
                HStack(spacing: 6) {
                    if isRescanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    Text(isRescanning ? "Rescanning…" : "Rescan with a hint")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(isRescanning)
            .accessibilityIdentifier("review.rescan")
        }
    }

    private var progressFraction: Double {
        guard progress.1 > 0 else { return 0 }
        return Double(progress.0) / Double(progress.1)
    }
}

// MARK: - Edit sheet

private struct EditDraftSheet: View {
    @Binding var draft: ExtractedDraft
    let categories: [TxCategory]
    let accounts: [Account]
    @Binding var selectedAccountID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Payee") {
                    TextField("Payee", text: $draft.payee)
                }
                Section("Amount") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .onAppear { amountText = (draft.amount as NSDecimalNumber).stringValue }
                        .onChange(of: amountText) { _, new in
                            let cleaned = new.replacingOccurrences(of: ",", with: ".")
                            if let d = Decimal(string: cleaned) { draft.amount = d }
                        }
                }
                Section("When") {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                }
                Section("Category") {
                    Picker("Category", selection: $draft.suggestedCategory) {
                        Text("None").tag(String?.none)
                        ForEach(categories.filter { $0.kind == (draft.amount < 0 ? .expense : .income) }) { c in
                            Text("\(c.emoji) \(c.name)").tag(Optional(c.name))
                        }
                    }
                }
                if !accounts.isEmpty {
                    Section("Account") {
                        Picker("Account", selection: $selectedAccountID) {
                            ForEach(accounts) { a in
                                Label(a.name, systemImage: a.kind.systemImage)
                                    .tag(Optional(a.id))
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Rescan sheet

private struct RescanSheet: View {
    @Binding var hint: String
    @Binding var isRunning: Bool
    @Binding var error: String?
    let onRescan: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "e.g. 'the total is the bottom-right figure, not the subtotal' or 'this is a refund, not a charge'",
                        text: $hint,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                } header: {
                    Text("What did the AI get wrong?")
                } footer: {
                    Text("BudgetBot will re-read the same receipt with this hint and propose a corrected version of this transaction.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Rescan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRunning)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onRescan()
                    } label: {
                        if isRunning {
                            ProgressView()
                        } else {
                            Text("Rescan").bold()
                        }
                    }
                    .disabled(isRunning || hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ConfidencePill: View {
    let value: Double
    var body: some View {
        let pct = Int((value * 100).rounded())
        Text("\(pct)% confident")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch value {
        case ..<0.5: return .red
        case ..<0.8: return .orange
        default:     return .green
        }
    }
}
