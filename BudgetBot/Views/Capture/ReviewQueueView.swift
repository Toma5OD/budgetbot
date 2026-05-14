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
                        onAccept: { acceptCurrent() },
                        onSkip:   { skipCurrent() },
                        onEdit:   { editingDraft = draft },
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
        commit(draft: draft, in: job)
        advance(job: job)
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

    private func commit(draft: ExtractedDraft, in job: CaptureJob) {
        let preferredAccount = accounts.first { $0.id == selectedAccountID }
            ?? CaptureViewModel.matchAccount(for: draft, in: accounts)
            ?? accounts.first
        guard let acc = preferredAccount else { return }

        let cat = CaptureViewModel.matchCategory(for: draft, in: categories)
        let (snapRate, snapBase) = CaptureViewModel.snapshotFX(
            from: draft.currency,
            to: job.baseCurrency,
            rates: fx.rates
        )
        let payment = Transaction.PaymentMethod(rawValue: draft.paymentMethod.rawValue) ?? .unknown

        // Reassign the job's first attachment to the first Transaction we create.
        let attachmentToUse: Attachment? = {
            if draftIndex == 0 { return (job.inputs ?? []).first }
            return nil
        }()
        if let att = attachmentToUse { att.captureJob = nil }

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
                let liCat = li.category.flatMap { name in
                    categories.first { $0.name.lowercased() == name.lowercased() }
                } ?? cat
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

        try? context.save()
    }
}

// MARK: - Card

private struct DraftReviewCard: View {
    let draft: ExtractedDraft
    let accounts: [Account]
    @Binding var selectedAccountID: UUID?
    let onAccept: () -> Void
    let onSkip:   () -> Void
    let onEdit:   () -> Void
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

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onAccept) {
                    Label("Accept", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
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
