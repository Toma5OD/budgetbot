import SwiftUI
import SwiftData

/// "Itemise with AI" — describe what an existing charge was for and let
/// the AI break it into line items. The classic case: a bank charge
/// ("Centra €4") that doesn't list what you bought. You type "two
/// lighters", the AI returns 2 × Lighter at €2, and on accept they're
/// saved as splits on the transaction.
///
/// It's honest about coverage: if what you describe doesn't account for
/// the whole charge, the shortfall shows as an explicit "Unaccounted"
/// line rather than the AI inflating prices to hit the total. If the
/// items somehow exceed the charge, you decide (scale to fit or redo) —
/// the app never silently changes your numbers.
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
    @State private var result: ItemisationResult?
    @State private var isRunning = false
    @State private var errorMessage: String?

    /// Positive magnitude of the charge.
    private var total: Decimal { tx.amount < 0 ? -tx.amount : tx.amount }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextCard
                    if result == nil {
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

            Text("Describe just what you remember — anything left over stays as an “Unaccounted” line you can keep or rename.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if let result {
            VStack(alignment: .leading, spacing: 12) {
                Text("Proposed items")
                    .font(.subheadline.bold())

                VStack(spacing: 0) {
                    let lines = result.lines
                    ForEach(lines) { line in
                        lineRow(line, isRemainder: isRemainder(line, in: result))
                        if line.id != lines.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .themedCard()

                statusRow(result)
                actions(result)
            }
        }
    }

    private func lineRow(_ line: ItemisedLine, isRemainder: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(line.quantity > 1 ? "\(line.quantity) × \(line.description)" : line.description)
                    .font(.callout)
                    .foregroundStyle(isRemainder ? .secondary : .primary)
                if line.quantity > 1 {
                    Text("\(CurrencyFormatter.string(for: line.unitAmount, currency: tx.currency)) each")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if isRemainder {
                    Text("not described — rename or remove after adding")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else if let cat = line.category, !cat.isEmpty {
                    Text(cat).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(CurrencyFormatter.string(for: line.amount, currency: tx.currency))
                .font(.callout.monospacedDigit())
                .foregroundStyle(isRemainder ? .secondary : .primary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusRow(_ result: ItemisationResult) -> some View {
        switch result.status {
        case .balanced, .under:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Adds up to \(CurrencyFormatter.string(for: total, currency: tx.currency))")
                Spacer()
            }
            .font(.caption.bold())
            .foregroundStyle(theme.current.incomeColor)
        case .over(let excess):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("These add up to \(CurrencyFormatter.string(for: result.sum, currency: tx.currency)) — \(CurrencyFormatter.string(for: excess, currency: tx.currency)) more than this charge. Scale them to fit, or redo with different wording.")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func actions(_ result: ItemisationResult) -> some View {
        switch result.status {
        case .balanced, .under:
            Button { commit(result) } label: {
                Label("Add \(result.lines.count) item\(result.lines.count == 1 ? "" : "s")",
                      systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("itemise.commit")
        case .over:
            Button {
                let scaled = AIService.proportionalScale(result.lines, to: total)
                self.result = AIService.settle(scaled, to: total)
            } label: {
                Label("Scale to fit \(CurrencyFormatter.string(for: total, currency: tx.currency))",
                      systemImage: "arrow.down.right.and.arrow.up.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }

        Button("Redo") {
            self.result = nil
            errorMessage = nil
        }
        .frame(maxWidth: .infinity)
    }

    /// The "Unaccounted" remainder is the last line when the status is
    /// `.under`. Identify it so we can render it as the soft filler line.
    private func isRemainder(_ line: ItemisedLine, in result: ItemisationResult) -> Bool {
        if case .under = result.status { return line.id == result.lines.last?.id }
        return false
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
            result = AIService.settle(lines, to: total)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commit(_ result: ItemisationResult) {
        // Splits carry the transaction's sign (negative for an expense).
        let sign: Decimal = tx.amount < 0 ? -1 : 1
        for line in result.lines {
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
