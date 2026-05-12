import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var filter: Filter = .all
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", income = "In", expense = "Out"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    ForEach(grouped, id: \.0) { day, items in
                        Section(day) {
                            ForEach(items) { tx in
                                NavigationLink(value: tx) {
                                    TransactionRow(tx: tx)
                                }
                            }
                            .onDelete { offsets in
                                for idx in offsets {
                                    context.delete(items[idx])
                                }
                                try? context.save()
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $search, prompt: "Search payees & notes")
                .navigationDestination(for: Transaction.self) { tx in
                    TransactionDetailView(tx: tx)
                }
            }
            .navigationTitle("Activity")
        }
    }

    private var filtered: [Transaction] {
        transactions.filter { tx in
            let matchFilter: Bool = {
                switch filter {
                case .all:     return true
                case .income:  return tx.amount > 0
                case .expense: return tx.amount < 0
                }
            }()
            let matchSearch: Bool = search.isEmpty
                || tx.payee.localizedCaseInsensitiveContains(search)
                || (tx.note?.localizedCaseInsensitiveContains(search) ?? false)
            return matchFilter && matchSearch
        }
    }

    private var grouped: [(String, [Transaction])] {
        let df = DateFormatter()
        df.dateStyle = .medium
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { tx in
            cal.startOfDay(for: tx.date)
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { (df.string(from: $0.key), $0.value) }
    }
}

struct TransactionRow: View {
    let tx: Transaction
    var body: some View {
        HStack {
            Text(tx.category?.emoji ?? "🧾")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.payee).font(.body)
                HStack(spacing: 4) {
                    if let cat = tx.category {
                        Text(cat.name)
                    }
                    if let acc = tx.account {
                        Text("· \(acc.name)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))
                .monospacedDigit()
                .foregroundStyle(tx.amount < 0 ? .red : .green)
        }
    }
}
