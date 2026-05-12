import SwiftUI
import SwiftData
import PDFKit

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
                Picker("Category", selection: $tx.category) {
                    Text("None").tag(TxCategory?.none)
                    ForEach(categories.filter { $0.kind == (tx.amount < 0 ? .expense : .income) }) { c in
                        Text("\(c.emoji) \(c.name)").tag(Optional(c))
                    }
                }
                TextField("Note", text: Binding(
                    get: { tx.note ?? "" },
                    set: { tx.note = $0.isEmpty ? nil : $0 }
                ))
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
        .navigationTitle(tx.payee)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { try? context.save() }
            }
        }
    }
}

private struct AttachmentPreview: View {
    let attachment: Attachment

    var body: some View {
        switch attachment.kind {
        case .image:
            if let data = attachment.data, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
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
            Text(attachment.text ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PDFKitRepresented: UIViewRepresentable {
    let doc: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = doc
        v.autoScales = true
        return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = doc
    }
}
