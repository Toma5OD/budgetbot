import SwiftUI
import SwiftData
import PDFKit

/// Edit a Transaction. If it's split, edit the per-split categories too.
struct TransactionDetailView: View {
    @Bindable var tx: Transaction
    @Environment(\.modelContext) private var context
    @Query private var categories: [TxCategory]
    @Query(filter: #Predicate<Account> { !$0.archived }) private var accounts: [Account]

    var body: some View {
        Form {
            Section("Amount") {
                HStack {
                    Text(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))
                        .font(.largeTitle.bold())
                        .foregroundStyle(tx.amount < 0 ? .red : .green)
                        .monospacedDigit()
                    Spacer()
                }
            }

            Section("Details") {
                TextField("Payee", text: $tx.payee)
                DatePicker("Date", selection: $tx.date, displayedComponents: [.date, .hourAndMinute])
                Picker("Account", selection: $tx.account) {
                    Text("None").tag(Account?.none)
                    ForEach(accounts) { a in
                        Text(a.name).tag(Optional(a))
                    }
                }
                Picker("Paid with", selection: Binding(
                    get: { tx.paymentMethod },
                    set: { tx.paymentMethod = $0 }
                )) {
                    ForEach(Transaction.PaymentMethod.allCases, id: \.self) { m in
                        Label(m.displayName, systemImage: m.systemImage).tag(m)
                    }
                }
                if tx.paymentMethod == .card {
                    TextField("Card brand (Visa, Mastercard…)", text: Binding(
                        get: { tx.cardBrand ?? "" },
                        set: { tx.cardBrand = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Card last 4 digits", text: Binding(
                        get: { tx.cardLast4 ?? "" },
                        set: {
                            let digits = $0.filter(\.isNumber).prefix(4)
                            tx.cardLast4 = digits.count == 4 ? String(digits) : nil
                        }
                    ))
                    .keyboardType(.numberPad)
                }
                if tx.splitItems.isEmpty {
                    Picker("Category", selection: $tx.category) {
                        Text("None").tag(TxCategory?.none)
                        ForEach(categories.filter { $0.kind == (tx.amount < 0 ? .expense : .income) }) { c in
                            Text("\(c.emoji) \(c.name)").tag(Optional(c))
                        }
                    }
                }
                TextField("Note", text: Binding(
                    get: { tx.note ?? "" },
                    set: { tx.note = $0.isEmpty ? nil : $0 }
                ))
            }

            if !tx.splitItems.isEmpty {
                Section("Splits (\(tx.splitItems.count))") {
                    ForEach(tx.splitItems.sorted { $0.createdAt < $1.createdAt }) { split in
                        @Bindable var bound = split
                        SplitEditor(split: bound, currency: tx.currency, categories: categories)
                    }
                    Button {
                        let s = Split(description: "Item", amount: 0, transaction: tx)
                        context.insert(s)
                    } label: { Label("Add split", systemImage: "plus.circle.fill") }
                    Button(role: .destructive) {
                        for s in tx.splitItems { context.delete(s) }
                    } label: { Label("Merge into single category", systemImage: "rectangle.compress.vertical") }
                }
            } else {
                Section {
                    Button {
                        // Convert to split by seeding one split mirroring the headline.
                        let s = Split(
                            description: tx.payee,
                            amount: tx.amount,
                            category: tx.category,
                            transaction: tx
                        )
                        context.insert(s)
                        tx.category = nil
                    } label: { Label("Split into multiple categories", systemImage: "rectangle.split.3x1") }
                }
            }

            if let att = tx.attachment {
                Section("Source") {
                    AttachmentPreview(attachment: att)
                }
            }

            HindsightRatingSection(tx: tx)

            RegretSection(tx: tx)

            Section {
                Toggle("Confirmed", isOn: $tx.confirmed)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(tx.payee)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { try? context.save() }
            }
        }
    }
}

private struct HindsightRatingSection: View {
    @Bindable var tx: Transaction
    @Environment(\.modelContext) private var context

    /// Cached series-size lookup. Recomputed when the transaction's
    /// `recurringRuleID` changes (i.e. when the periodic scan back-
    /// links it).
    @State private var seriesSiblings: Int = 0

    var body: some View {
        Section {
            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        // Tap the same star twice to clear.
                        if tx.hindsightRating == star {
                            tx.hindsightRating = nil
                            tx.hindsightRatedAt = nil
                        } else {
                            tx.hindsightRating = star
                            tx.hindsightRatedAt = .now
                            SeriesLinker.propagate(ratingFrom: tx, in: context)
                        }
                        try? context.save()
                    } label: {
                        Image(systemName: (tx.hindsightRating ?? 0) >= star
                              ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(starTint(star))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let rated = tx.hindsightRatedAt {
                    Text(rated, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("In hindsight…")
        } footer: {
            Text(footerText)
        }
        .onAppear {
            seriesSiblings = SeriesLinker.seriesSize(for: tx, in: context)
        }
    }

    private func starTint(_ star: Int) -> Color {
        guard let rating = tx.hindsightRating, rating >= star else {
            return .gray.opacity(0.4)
        }
        switch rating {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return Color(red: 0.5, green: 0.8, blue: 0.3)
        default: return .green
        }
    }

    private var footerText: String {
        let seriesNote = seriesSiblings > 0
            ? " Part of a recurring series — rating this also rates the other \(seriesSiblings)."
            : ""
        switch tx.hindsightRating {
        case nil: return "Tap a star to score this purchase 1-5. Powers the Rate-in-Hindsight game and analytics." + seriesNote
        case 1: return "Total L." + seriesNote
        case 2: return "Wouldn't again." + seriesNote
        case 3: return "Did its job." + seriesNote
        case 4: return "Worth it." + seriesNote
        case 5: return "No notes." + seriesNote
        default: return ""
        }
    }
}

private struct RegretSection: View {
    @Bindable var tx: Transaction

    var body: some View {
        Section {
            Toggle(isOn: $tx.isRegret) {
                Label("Mark as silly purchase", systemImage: "trophy.fill")
            }
            if tx.isRegret {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vibe").font(.caption.bold()).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Transaction.regretEmojis, id: \.0) { emoji, label in
                                Button {
                                    tx.regretEmoji = tx.regretEmoji == emoji ? nil : emoji
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(emoji).font(.title2)
                                        Text(label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(tx.regretEmoji == emoji
                                                  ? Color.accentColor.opacity(0.18)
                                                  : Color.gray.opacity(0.08))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("What were you thinking? (optional)", text: Binding(
                        get: { tx.regretNote ?? "" },
                        set: { tx.regretNote = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(1...3)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Hall of Shame")
        } footer: {
            if tx.isRegret {
                Text("This shows up in the Hall of Shame screen so you can roast yourself later.")
            }
        }
    }
}

private struct SplitEditor: View {
    @Bindable var split: Split
    let currency: String
    let categories: [TxCategory]

    @State private var amountText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Description", text: $split.itemDescription).font(.callout)
                Spacer()
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 90)
                    .onAppear { amountText = (split.amount as NSDecimalNumber).stringValue }
                    .onChange(of: amountText) { _, new in
                        let cleaned = new.replacingOccurrences(of: ",", with: ".")
                        if let d = Decimal(string: cleaned) { split.amount = d }
                    }
            }
            Picker("Category", selection: $split.category) {
                Text("None").tag(TxCategory?.none)
                ForEach(categories.filter { $0.kind == (split.amount < 0 ? .expense : .income) }) { c in
                    Text("\(c.emoji) \(c.name)").tag(Optional(c))
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

private struct AttachmentPreview: View {
    let attachment: Attachment
    var body: some View {
        switch attachment.kind {
        case .image:
            if let data = attachment.data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Missing image data").foregroundStyle(.secondary)
            }
        case .pdf:
            if let data = attachment.data, let doc = PDFDocument(data: data) {
                PDFKitRepresented(doc: doc).frame(height: 360)
            } else {
                Text("Missing PDF data").foregroundStyle(.secondary)
            }
        case .text:
            Text(attachment.text ?? "").font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct PDFKitRepresented: UIViewRepresentable {
    let doc: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView(); v.document = doc; v.autoScales = true; return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) { uiView.document = doc }
}
