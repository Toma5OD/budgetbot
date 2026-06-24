import SwiftUI
import SwiftData

/// Add an expense with no receipt — just type or say it. "Haircut €30"
/// becomes a €30 Haircut; "2 coffees €13" becomes a €13 charge with two
/// editable €6.50 coffee line items. Local parse, no AI, no key.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @Query(filter: #Predicate<Account> { !$0.archived }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var text = ""
    @State private var selectedAccountID: UUID?
    @State private var speech = SpeechRecognizer()

    private var base: String {
        profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? Currencies.localeDefault
    }
    private var parsed: QuickEntry? { QuickEntryParser.parse(text) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    entryRow
                    if let err = speech.errorMessage {
                        Label(err, systemImage: "mic.slash.fill")
                            .font(.caption).foregroundStyle(.orange)
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
                    .lineLimit(1...3)
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
                 : "Type it, or tap the mic and say it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let p = parsed {
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
        } else {
            Label("Add an amount, e.g. “Haircut €30”.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
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
            Label("Add expense", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(parsed == nil)
        .accessibilityIdentifier("quickadd.add")
    }

    // MARK: - Create

    private func add() {
        guard let p = parsed else { return }
        speech.stop()
        let acct = accounts.first { $0.id == selectedAccountID }
        let tx = Transaction(
            amount: -p.amount,
            currency: base,
            payee: p.payee,
            confirmed: true,
            account: acct
        )
        context.insert(tx)

        if p.quantity > 1 {
            // Expand into individual editable line items.
            let lines = AIService.expandQuantities(
                [ItemisedLine(description: p.payee, quantity: p.quantity,
                              amount: p.amount, category: nil)]
            )
            for l in lines {
                context.insert(Split(description: l.description,
                                     amount: -l.amount, quantity: 1, transaction: tx))
            }
        }
        try? context.save()
        dismiss()
    }
}
