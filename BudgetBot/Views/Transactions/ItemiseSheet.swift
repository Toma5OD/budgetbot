import SwiftUI
import SwiftData

/// "Itemise with AI" — describe what an existing charge was for and let
/// the AI break it into line items. The classic case: a bank charge
/// ("Centra €4") that doesn't list what you bought. You type "two
/// lighters", the AI returns 2 × Lighter at €2, and on accept they're
/// saved as splits on the transaction.
///
/// The proposed items are fully editable before you commit — rename,
/// retype an amount, add or remove a line — and a live readout shows
/// whether they add up to the charge, with one-tap "scale to fit". A
/// shortfall starts life as an "Unaccounted" line you can keep or rename.
///
/// Committing replaces any existing splits, so this doubles as a
/// re-itemise. The caller gates on an API key + AI consent first.
struct ItemiseSheet: View {
    @Bindable var tx: Transaction
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Query private var categories: [TxCategory]

    @State private var description = ""
    @State private var draft: [DraftLine] = []
    @State private var hasRun = false
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var showConsent = false
    @State private var showNeedsKey = false

    /// Positive magnitude of the charge.
    private var total: Decimal { tx.amount < 0 ? -tx.amount : tx.amount }

    /// One editable proposed item. `amountText` is the line total.
    private struct DraftLine: Identifiable {
        let id = UUID()
        var description: String
        var amountText: String
        var quantity: Int
        var category: String?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextCard
                    if hasRun { results } else { prompt }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Itemise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showConsent) {
                AIConsentSheet { Task { await run() } }
            }
            .alert("AI key needed", isPresented: $showNeedsKey) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Describing it for the AI needs an Anthropic API key (Settings → AI). You can still add the items by hand without one.")
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
            Text("Describe it and let AI itemise")
                .font(.subheadline.bold())
            TextField("e.g. two lighters · a coffee and a roll · 3 pints",
                      text: $description, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("itemise.description")

            Button {
                startAI()
            } label: {
                HStack {
                    if isRunning { ProgressView().tint(.white) }
                    Text(isRunning ? "Itemising…" : "Itemise with AI")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
            .accessibilityIdentifier("itemise.ai")

            Text("You can edit everything before saving, and anything left over becomes an “Unaccounted” line you can keep or rename.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                VStack { Divider() }
                Text("or").font(.caption).foregroundStyle(.tertiary)
                VStack { Divider() }
            }
            .padding(.vertical, 2)

            Button {
                startManual()
            } label: {
                Label("Add items by hand", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("itemise.manual")
        }
    }

    // MARK: - Results (editable)

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items")
                .font(.subheadline.bold())

            VStack(spacing: 0) {
                ForEach($draft) { $line in
                    editableRow($line)
                    if line.id != draft.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .themedCard()

            Button {
                draft.append(DraftLine(description: "", amountText: "", quantity: 1, category: nil))
            } label: {
                Label("Add item", systemImage: "plus.circle")
                    .font(.callout)
            }

            balanceRow
            if abs(difference) >= Decimal(string: "0.005") ?? 0 {
                Button { scaleToFit() } label: {
                    Label("Scale to fit \(CurrencyFormatter.string(for: total, currency: tx.currency))",
                          systemImage: "arrow.down.right.and.arrow.up.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button { commit() } label: {
                Label("Add to charge", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasAnyLine)
            .accessibilityIdentifier("itemise.commit")

            Button("Redo") { hasRun = false; draft = []; errorMessage = nil }
                .frame(maxWidth: .infinity)
        }
    }

    private func editableRow(_ line: Binding<DraftLine>) -> some View {
        HStack(spacing: 8) {
            if line.wrappedValue.quantity > 1 {
                Text("×\(line.wrappedValue.quantity)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            TextField("Item", text: line.description)
                .font(.callout)
            TextField("0", text: line.amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.callout.monospacedDigit())
                .frame(width: 76)
            Button(role: .destructive) {
                draft.removeAll { $0.id == line.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var balanceRow: some View {
        let diff = difference
        HStack {
            Text("Items").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(CurrencyFormatter.string(for: itemsSum, currency: tx.currency))
                .font(.caption.bold().monospacedDigit())
        }
        .padding(.horizontal, 4)

        Group {
            if abs(diff) < (Decimal(string: "0.005") ?? 0) {
                Label("Adds up to the \(CurrencyFormatter.string(for: total, currency: tx.currency)) charge",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(theme.current.incomeColor)
            } else if diff > 0 {
                Label("\(CurrencyFormatter.string(for: diff, currency: tx.currency)) of the charge isn't itemised yet",
                      systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            } else {
                Label("\(CurrencyFormatter.string(for: -diff, currency: tx.currency)) more than the charge",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    // MARK: - Derived

    private var parsed: [(desc: String, amount: Decimal, qty: Int, category: String?)] {
        draft.map { d in
            let amt = Decimal(string: d.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
            return (d.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    max(0, amt), d.quantity, d.category)
        }
    }
    private var itemsSum: Decimal { parsed.reduce(Decimal(0)) { $0 + $1.amount } }
    private var difference: Decimal { total - itemsSum }
    private var hasAnyLine: Bool { parsed.contains { !$0.desc.isEmpty || $0.amount > 0 } }

    // MARK: - Actions

    /// AI path — gated on a key + consent at the point of use, so the
    /// manual path below stays reachable without either.
    private func startAI() {
        switch AIConsent.gate() {
        case .needsKey:     showNeedsKey = true
        case .needsConsent: showConsent = true
        case .proceed:      Task { await run() }
        }
    }

    /// Manual path — no AI, no key. Seed one line for the whole charge;
    /// the user renames it and adds more, with the live balance keeping
    /// them honest.
    private func startManual() {
        draft = [DraftLine(description: "", amountText: plainAmount(total),
                           quantity: 1, category: nil)]
        errorMessage = nil
        hasRun = true
    }

    private func run() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        guard NetworkMonitor.shared.isOnline else {
            errorMessage = "You're offline — itemising needs a connection. Try again when you're back online."
            return
        }
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
            let settled = AIService.settle(lines, to: total)
            // Expand "2 × Coffee" into two editable Coffee lines.
            let expanded = AIService.expandQuantities(settled.lines)
            draft = expanded.map {
                DraftLine(description: $0.description,
                          amountText: plainAmount($0.amount),
                          quantity: 1,
                          category: $0.category)
            }
            hasRun = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scaleToFit() {
        let lines = parsed.map {
            ItemisedLine(description: $0.desc, quantity: $0.qty, amount: $0.amount, category: $0.category)
        }
        let scaled = AIService.proportionalScale(lines, to: total)
        for (i, s) in scaled.enumerated() where i < draft.count {
            draft[i].amountText = plainAmount(s.amount)
        }
    }

    private func commit() {
        // Replace any existing splits so this also serves as re-itemise.
        for s in tx.splitItems { context.delete(s) }

        let sign: Decimal = tx.amount < 0 ? -1 : 1
        for p in parsed where !(p.desc.isEmpty && p.amount == 0) {
            let matched = categories.first {
                $0.name.compare(p.category ?? "", options: .caseInsensitive) == .orderedSame
            }
            let split = Split(
                description: p.desc.isEmpty ? "Item" : p.desc,
                amount: p.amount * sign,
                quantity: p.qty,
                category: matched ?? tx.category,
                transaction: tx
            )
            context.insert(split)
        }
        tx.category = nil
        try? context.save()
        dismiss()
    }

    /// Plain amount string for the editable field — "4", "2.5", "20.99".
    private func plainAmount(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}
