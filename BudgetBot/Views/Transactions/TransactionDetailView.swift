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
                if tx.splits.isEmpty {
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

            if !tx.splits.isEmpty {
                Section("Splits (\(tx.splits.count))") {
                    ForEach(tx.splits.sorted { $0.createdAt < $1.createdAt }) { split in
                        @Bindable var bound = split
                        SplitEditor(split: bound, currency: tx.currency, categories: categories)
                    }
                    Button {
                        let s = Split(description: "Item", amount: 0, transaction: tx)
                        context.insert(s)
                    } label: { Label("Add split", systemImage: "plus.circle.fill") }
                    Button(role: .destructive) {
                        for s in tx.splits { context.delete(s) }
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
