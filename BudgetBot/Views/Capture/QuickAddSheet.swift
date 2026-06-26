import SwiftUI
import SwiftData

/// Add an expense with no receipt — just type or say it. When an AI key is
/// set, the text is sent to the same extraction pipeline receipts use, so a
/// spoken sentence ("got a haircut and a jersey off the same guy, paid cash,
/// last Wednesday at 2:30") becomes a properly dated, itemised, categorised
/// transaction. With no key/consent it falls back to a quick local parse
/// ("Haircut €30" → a €30 Haircut) that works offline.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Environment(CaptureQueueService.self) private var queue

    @Query(filter: #Predicate<Account> { !$0.archived }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var categories: [TxCategory]

    @State private var text = ""
    @State private var selectedAccountID: UUID?
    @State private var speech = SpeechRecognizer()

    private var base: String {
        profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? Currencies.localeDefault
    }
    private var parsed: QuickEntry? { QuickEntryParser.parse(text) }

    /// Whether we can use the AI to interpret free-form text. Needs a key and
    /// the user's data-sharing consent; otherwise we use the local parser.
    private var aiAvailable: Bool {
        (KeychainService.shared.get(.anthropicAPIKey)?.isEmpty == false) && AIConsent.isGranted
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canAdd: Bool {
        aiAvailable ? !trimmed.isEmpty : (parsed != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    entryRow
                    if let err = speech.errorMessage {
                        Label(err, systemImage: "mic.slash.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if speech.canRetry {
                        Button {
                            speech.retry()
                        } label: {
                            Label(speech.isTranscribing ? "Retrying…" : "Retry transcription",
                                  systemImage: "arrow.clockwise")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(speech.isTranscribing)
                        .accessibilityHint("Re-sends your last recording without recording again")
                    }
                    preview
                    if !accounts.isEmpty { accountPicker }
                    Spacer(minLength: 0)
                    addButton
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: speech.transcript) { _, t in if !t.isEmpty { text = t } }
            .onAppear { selectedAccountID = accounts.first?.id }
            .onDisappear { speech.stop() }
        }
    }

    // MARK: - Entry

    private var entryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What did you spend on?").font(.subheadline.bold())
            HStack(spacing: 10) {
                TextField("Haircut €30 · 2 coffees €13", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("quickadd.text")
                Button {
                    speech.toggle()
                } label: {
                    if speech.isTranscribing {
                        ProgressView().frame(width: 34, height: 34)
                    } else {
                        Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(speech.isRecording ? .red : theme.current.tint)
                            .symbolEffect(.pulse, isActive: speech.isRecording)
                    }
                }
                .disabled(speech.isTranscribing)
                .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate")
            }
            Text(speech.isTranscribing ? "Transcribing…"
                 : speech.isRecording ? "Listening… tap stop when you're done."
                 : aiAvailable ? "Type it or say it — even several things at once."
                 : "Type it, or tap the mic and say it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if aiAvailable {
            smartAddHint
        } else if let p = parsed {
            localPreview(p)
        } else {
            Label("Add an amount, e.g. “Haircut €30”.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var smartAddHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(theme.current.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Smart add").font(.subheadline.bold())
                Text("BudgetBot reads what you wrote and pulls out the merchant, each item, the amount, the date and how you paid — and asks you if anything's unclear.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    @ViewBuilder
    private func localPreview(_ p: QuickEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(p.payee).font(.headline)
                Spacer()
                Text(CurrencyFormatter.string(for: p.amount, currency: base))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(theme.current.expenseColor)
            }
            if p.quantity > 1 {
                let each = p.amount / Decimal(p.quantity)
                Divider()
                ForEach(0..<p.quantity, id: \.self) { _ in
                    HStack {
                        Text(p.payee).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.string(for: each, currency: base))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Split into \(p.quantity) items — edit any of them after saving.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    private var accountPicker: some View {
        HStack {
            Text("Account").font(.subheadline)
            Spacer()
            Menu {
                Button("No account") { selectedAccountID = nil }
                ForEach(accounts) { a in
                    Button(a.name) { selectedAccountID = a.id }
                }
            } label: {
                let name = accounts.first { $0.id == selectedAccountID }?.name ?? "No account"
                HStack(spacing: 4) {
                    Text(name)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(theme.current.tint)
            }
        }
        .padding(14)
        .themedCard()
    }

    private var addButton: some View {
        Button { add() } label: {
            Label(aiAvailable ? "Add with AI" : "Add expense",
                  systemImage: aiAvailable ? "sparkles" : "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canAdd)
        .accessibilityIdentifier("quickadd.add")
    }

    // MARK: - Create

    private func add() {
        speech.stop()
        guard !trimmed.isEmpty else { return }
        if aiAvailable {
            enqueueForAI(trimmed)
        } else if let p = parsed {
            addLocally(p)
        } else {
            return
        }
        dismiss()
    }

    /// Hand the free-form text to the AI extraction queue — the same path
    /// receipts use. The AI returns properly dated, itemised, categorised
    /// drafts that auto-save when confident (YOLO) or land in review so the
    /// user can confirm. This is what makes "I got a haircut and a jersey…"
    /// resolve into the right transaction instead of one giant payee.
    private func enqueueForAI(_ raw: String) {
        let p = profiles.first
        let job = CaptureJob(
            defaultAccountID: selectedAccountID,
            aiModel: p?.aiModel ?? AIService.defaultModel,
            defaultCurrency: p?.defaultCurrency ?? base,
            baseCurrency: p?.baseCurrency ?? base,
            yoloMode: p?.yoloMode ?? false,
            critiqueMode: p?.critiqueMode ?? false,
            textNote: raw
        )
        context.insert(job)
        try? context.save()
        queue.pump()
    }

    /// Offline / no-key fallback: the quick regex parse. Finds one amount and
    /// uses the rest as the payee, with a best-effort merchant category.
    private func addLocally(_ p: QuickEntry) {
        let acct = accounts.first { $0.id == selectedAccountID }
        let category = MerchantCategory.resolve(p.payee).flatMap { name in
            categories.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
        }
        let tx = Transaction(
            // Stated date ("yesterday") if any, otherwise current date+time.
            date: p.date ?? .now,
            amount: -p.amount,
            currency: base,
            payee: p.payee,
            confirmed: true,
            account: acct
        )
        context.insert(tx)

        if p.quantity > 1 {
            let lines = AIService.expandQuantities(
                [ItemisedLine(description: p.payee, quantity: p.quantity,
                              amount: p.amount, category: nil)]
            )
            for l in lines {
                context.insert(Split(description: l.description,
                                     amount: -l.amount, quantity: 1,
                                     category: category, transaction: tx))
            }
        } else {
            tx.category = category
        }
        try? context.save()
    }
}
