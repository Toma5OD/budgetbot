import SwiftUI
import SwiftData

/// "Itemise with AI" — describe what an existing charge was for and let
/// the AI break the known total into line items. The classic case: a
/// bank charge ("Centra €4") that doesn't list what you bought. You type
/// "two lighters", the AI returns 2 × Lighter at €2, and on accept they're
/// saved as splits on the transaction.
///
/// The caller (TransactionDetailView) gates this on an API key + AI
/// consent before presenting, so this sheet just runs the request.
struct ItemiseSheet: View {
    @Bindable var tx: Transaction
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Query private var categories: [TxCategory]

    @State private var description = ""
    @State private var proposed: [ItemisedLine]?
    @State private var isRunning = false
    @State private var errorMessage: String?

    /// Positive magnitude of the charge — what the lines must sum to.
    private var total: Decimal { tx.amount < 0 ? -tx.amount : tx.amount }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextCard
                    if proposed == nil {
                        prompt
                    } else {
                        results
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Itemise with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Context

    private var contextCard: some View {
        HStack(spacing: 12) {
            BrandLogoView(name: tx.payee, fallbackEmoji: tx.category?.emoji ?? "🧾", size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(tx.payee).font(.headline)
                Text("Total \(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .themedCard()
    }

    // MARK: - Prompt

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What did you buy?")
                .font(.subheadline.bold())
            TextField("e.g. two lighters · a coffee and a roll · 3 pints",
                      text: $description, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("itemise.description")

            Button {
                Task { await run() }
            } label: {
                HStack {
                    if isRunning { ProgressView().tint(.white) }
                    Text(isRunning ? "Itemising…" : "Itemise")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)

            Text("The AI splits the **\(CurrencyFormatter.string(for: total, currency: tx.currency))** total into items that add back up to it. You can redo if it's off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Results

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed items")
                .font(.subheadline.bold())

            VStack(spacing: 0) {
                let lines = proposed ?? []
                ForEach(lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.quantity > 1
                                 ? "\(line.quantity) × \(line.description)"
                                 : line.description)
                                .font(.callout)
                            if line.quantity > 1 {
                                Text("\(CurrencyFormatter.string(for: line.unitAmount, currency: tx.currency)) each")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if let cat = line.category, !cat.isEmpty {
                                Text(cat).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(CurrencyFormatter.string(for: line.amount, currency: tx.currency))
                            .font(.callout.monospacedDigit())
                    }
                    .padding(.vertical, 8)
                    if line.id != lines.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .themedCard()

            HStack {
                Text("Sum").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(CurrencyFormatter.string(for: proposedSum, currency: tx.currency))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(proposedSum == total ? theme.current.incomeColor : .orange)
            }
            .padding(.horizontal, 4)

            Button {
                commit()
            } label: {
                Label("Add \(proposed?.count ?? 0) item\((proposed?.count ?? 0) == 1 ? "" : "s")",
                      systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("itemise.commit")

            Button("Redo") {
                proposed = nil
                errorMessage = nil
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var proposedSum: Decimal {
        (proposed ?? []).reduce(Decimal(0)) { $0 + $1.amount }
    }

    // MARK: - Actions

    private func run() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        guard let service = AIService.fromKeychain() else {
            errorMessage = "Add your Anthropic API key in Settings → AI to use this."
            return
        }
        do {
            let lines = try await service.itemise(
                merchant: tx.payee,
                total: total,
                currency: tx.currency,
                description: description,
                categories: categories.map(\.name)
            )
            guard !lines.isEmpty else {
                errorMessage = "Couldn't make items out of that. Try describing it differently."
                return
            }
            proposed = lines
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commit() {
        guard let lines = proposed else { return }
        // Splits carry the transaction's sign (negative for an expense).
        let sign: Decimal = tx.amount < 0 ? -1 : 1
        for line in lines {
            let matched = categories.first {
                $0.name.compare(line.category ?? "", options: .caseInsensitive) == .orderedSame
            }
            let split = Split(
                description: line.description,
                amount: line.amount * sign,
                quantity: line.quantity,
                category: matched ?? tx.category,
                transaction: tx
            )
            context.insert(split)
        }
        // The transaction is now itemised — drop the single headline
        // category so totals come from the splits.
        tx.category = nil
        try? context.save()
        dismiss()
    }
}
