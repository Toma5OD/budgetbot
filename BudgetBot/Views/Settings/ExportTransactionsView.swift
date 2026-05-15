import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Renders a CSV of every confirmed transaction and offers it via a
/// share sheet. Lives behind Settings → Data → "Export transactions"
/// — a tax-season / accountant-handoff path.
struct ExportTransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @Query(filter: #Predicate<Transaction> { $0.confirmed },
           sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var generating = false
    @State private var exportURL: URL?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                stats
                actionButton
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Export transactions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { exportURL.map(ExportItem.init) },
            set: { exportURL = $0?.url })
        ) { item in
            ShareSheet(items: [item.url])
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tablecells.fill")
                .font(.system(size: 44))
                .foregroundStyle(theme.current.tint)
            Text("CSV export").font(.title3.bold())
            Text("One row per transaction, RFC-4180. Open in Numbers / Excel / Google Sheets, or hand to your accountant.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var stats: some View {
        HStack(spacing: 14) {
            stat("Confirmed", "\(transactions.count)")
            stat("Earliest", transactions.last.map {
                $0.date.formatted(date: .abbreviated, time: .omitted)
            } ?? "—")
            stat("Latest", transactions.first.map {
                $0.date.formatted(date: .abbreviated, time: .omitted)
            } ?? "—")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.callout.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .themedCard()
    }

    private var actionButton: some View {
        Button {
            generate()
        } label: {
            HStack(spacing: 8) {
                if generating { ProgressView().tint(.white) }
                Text(generating ? "Generating…" : "Generate & share CSV")
                    .font(.callout.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.current.tint, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(generating || transactions.isEmpty)
    }

    private func generate() {
        generating = true
        error = nil
        defer { generating = false }
        let data = CSVExporter.transactionsCSV(transactions)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(CSVExporter.suggestedFilename())
        do {
            try data.write(to: url, options: [.atomic])
            exportURL = url
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ExportItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
