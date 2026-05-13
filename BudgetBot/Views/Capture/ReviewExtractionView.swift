import SwiftUI

struct ReviewExtractionView: View {
    let drafts: [ExtractedDraft]
    /// draftID -> existing transaction IDs that look like duplicates
    let duplicates: [UUID: [UUID]]
    let accounts: [Account]
    var onConfirm: ([ExtractedDraft], Account) -> Void
    var onCancel: () -> Void

    @State private var editable: [ExtractedDraft]
    @State private var selected: Set<UUID>
    @State private var defaultAccountID: UUID?

    init(drafts: [ExtractedDraft],
         duplicates: [UUID: [UUID]],
         accounts: [Account],
         onConfirm: @escaping ([ExtractedDraft], Account) -> Void,
         onCancel: @escaping () -> Void) {
        self.drafts = drafts
        self.duplicates = duplicates
        self.accounts = accounts
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _editable = State(initialValue: drafts)
        let nonDupes = drafts.filter { duplicates[$0.id] == nil }.map { $0.id }
        _selected = State(initialValue: Set(nonDupes))
        // Pre-pick from AI signals: cash hint → cash account; else first account.
        let preferred = Self.preferredAccount(forDrafts: drafts, in: accounts)
        _defaultAccountID = State(initialValue: preferred?.id ?? accounts.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                draftsSection
                paymentSection
            }
            .listStyle(.insetGrouped)

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    guard let id = defaultAccountID,
                          let acc = accounts.first(where: { $0.id == id }) else { return }
                    let chosen = editable.filter { selected.contains($0.id) }
                    onConfirm(chosen, acc)
                } label: {
                    Text("Save \(selected.count)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || defaultAccountID == nil)
            }
            .padding()
        }
    }

    // MARK: - Sections

    private var draftsSection: some View {
        Section("Found \(editable.count) transaction\(editable.count == 1 ? "" : "s")") {
            ForEach($editable) { $d in
                DraftRow(
                    draft: $d,
                    selected: bindingFor(d.id),
                    isDuplicate: duplicates[d.id] != nil
                )
            }
        }
    }

    @ViewBuilder
    private var paymentSection: some View {
        Section {
            if accounts.isEmpty {
                Text("Add a bank or cash account first (Accounts tab).")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(accounts) { a in
                        AccountChip(
                            account: a,
                            isSelected: a.id == defaultAccountID
                        ) {
                            defaultAccountID = a.id
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(paymentHeaderText)
        } footer: {
            if cashHint {
                Text("The receipt looks like a cash payment — we picked your cash account. Override if you used something else.")
            } else if cardHint {
                Text("The receipt looks like a card payment. Pick which card you used.")
            }
        }
    }

    private var paymentHeaderText: String {
        if cashHint { return "Paid with — cash detected" }
        if cardHint { return "Paid with — card detected" }
        return "Paid with"
    }

    private var cashHint: Bool {
        editable.contains { $0.paymentMethod == .cash }
    }
    private var cardHint: Bool {
        editable.contains { $0.paymentMethod == .card } && !cashHint
    }

    // MARK: - Helpers

    nonisolated private static func preferredAccount(
        forDrafts drafts: [ExtractedDraft],
        in accounts: [Account]
    ) -> Account? {
        if let cashDraft = drafts.first(where: { $0.paymentMethod == .cash }),
           let cashAcc = accounts.first(where: { $0.kind == .cash && $0.currency == cashDraft.currency })
            ?? accounts.first(where: { $0.kind == .cash }) {
            return cashAcc
        }
        return nil
    }

    private func bindingFor(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }
}

private struct AccountChip: View {
    let account: Account
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: account.kind.systemImage)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.subheadline.bold()).lineLimit(1)
                    Text(account.kind.displayName)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.tint.opacity(0.18) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.tint : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.tint : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pay with \(account.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

private extension Color {
    /// SwiftUI's `.tint` only resolves inside View bodies; expose the accent
    /// color directly for use in plain Color contexts above.
    static var tint: Color { Color.accentColor }
}

private struct DraftRow: View {
    @Binding var draft: ExtractedDraft
    @Binding var selected: Bool
    let isDuplicate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $selected).labelsHidden()
                    .accessibilityLabel(selected ? "Include this transaction" : "Skip this transaction")
                TextField("Payee", text: $draft.payee)
                    .font(.headline)
                Spacer()
                Text(CurrencyFormatter.string(for: draft.amount, currency: draft.currency))
                    .foregroundStyle(draft.amount < 0 ? .red : .green)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                DatePicker("", selection: $draft.date, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                if isDuplicate {
                    Label("Likely duplicate", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if let sug = draft.suggestedCategory {
                    Label(sug, systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ConfidencePill(value: draft.confidence)
            }

            DecimalField(amount: $draft.amount, currency: draft.currency)

            if !draft.lineItems.isEmpty {
                DisclosureGroup("Line items (\(draft.lineItems.count))") {
                    ForEach(draft.lineItems) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.description).font(.caption)
                                if let cat = item.category {
                                    Text(cat).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(CurrencyFormatter.string(for: item.amount, currency: draft.currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct DecimalField: View {
    @Binding var amount: Decimal
    let currency: String
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text("Amount")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onAppear { text = (amount as NSDecimalNumber).stringValue }
                .onChange(of: text) { _, new in
                    let cleaned = new.replacingOccurrences(of: ",", with: ".")
                    if let d = Decimal(string: cleaned) { amount = d }
                }
        }
    }
}

private struct ConfidencePill: View {
    let value: Double
    var body: some View {
        let pct = Int((value * 100).rounded())
        Text("\(pct)%")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("AI confidence \(pct) percent")
    }
    private var color: Color {
        switch value {
        case ..<0.5: return .red
        case ..<0.8: return .orange
        default:     return .green
        }
    }
}
