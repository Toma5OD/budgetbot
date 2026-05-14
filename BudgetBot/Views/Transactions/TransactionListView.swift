import SwiftUI
import SwiftData

/// Activity feed. Toggles between **Transactions** (one row per money
/// movement — bank-statement shape) and **Items** (a flat list of every
/// allocation, expanding splits where present).
struct TransactionListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var mode: Mode = .transactions
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var galleryGrouping: ReceiptsGalleryView.GroupBy = .date

    enum Mode: String, CaseIterable, Identifiable {
        case transactions = "Transactions", items = "Items", receipts = "Receipts"
        var id: String { rawValue }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", income = "In", expense = "Out"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if mode == .receipts {
                    Picker("", selection: $galleryGrouping) {
                        ForEach(ReceiptsGalleryView.GroupBy.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                } else {
                    Picker("", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                Group {
                    switch mode {
                    case .transactions: transactionsList
                    case .items:        itemsList
                    case .receipts:     ReceiptsGalleryView(groupBy: $galleryGrouping)
                    }
                }
                .animation(.snappy, value: mode)
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $search, prompt: "Search payees, items & notes")
            .navigationTitle("Activity")
            .appHeaderToolbar()
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(tx: tx)
            }
        }
    }

    // MARK: - Transactions list

    private var transactionsList: some View {
        List {
            ForEach(groupedTransactions, id: \.0) { day, items in
                Section(day) {
                    ForEach(items) { tx in
                        NavigationLink(value: tx) {
                            TransactionRow(tx: tx)
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets { context.delete(items[idx]) }
                        try? context.save()
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var filteredTransactions: [Transaction] {
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
                || tx.splitItems.contains { $0.itemDescription.localizedCaseInsensitiveContains(search) }
            return matchFilter && matchSearch && tx.confirmed
        }
    }

    private var groupedTransactions: [(String, [Transaction])] {
        let df = DateFormatter(); df.dateStyle = .medium
        let cal = Calendar.current
        let groups = Dictionary(grouping: filteredTransactions) { cal.startOfDay(for: $0.date) }
        return groups.sorted { $0.key > $1.key }
            .map { (df.string(from: $0.key), $0.value) }
    }

    // MARK: - Items list (splits expanded)

    private var itemsList: some View {
        List {
            ForEach(groupedItems, id: \.0) { catName, rows in
                Section(catName) {
                    ForEach(rows) { row in
                        NavigationLink(value: row.transaction) {
                            ItemRowView(row: row)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// One displayable row in the Items view — either a split or, for a
    /// transaction without splits, the transaction itself reinterpreted as a
    /// single item.
    struct ItemRow: Identifiable {
        let id: UUID
        let description: String
        let amount: Decimal
        let currency: String
        let date: Date
        let categoryName: String
        let categoryEmoji: String
        let transaction: Transaction
    }

    private var allItems: [ItemRow] {
        var rows: [ItemRow] = []
        for tx in transactions where tx.confirmed {
            if tx.splitItems.isEmpty {
                rows.append(ItemRow(
                    id: tx.id,
                    description: tx.payee,
                    amount: tx.amount,
                    currency: tx.currency,
                    date: tx.date,
                    categoryName: tx.category?.name ?? "Uncategorised",
                    categoryEmoji: tx.category?.emoji ?? "🧾",
                    transaction: tx
                ))
            } else {
                for s in tx.splitItems {
                    rows.append(ItemRow(
                        id: s.id,
                        description: s.itemDescription,
                        amount: s.amount,
                        currency: s.currency,
                        date: s.date,
                        categoryName: s.category?.name ?? "Uncategorised",
                        categoryEmoji: s.category?.emoji ?? "🧾",
                        transaction: tx
                    ))
                }
            }
        }
        return rows
    }

    private var filteredItems: [ItemRow] {
        allItems.filter { row in
            let matchFilter: Bool = {
                switch filter {
                case .all:     return true
                case .income:  return row.amount > 0
                case .expense: return row.amount < 0
                }
            }()
            let matchSearch: Bool = search.isEmpty
                || row.description.localizedCaseInsensitiveContains(search)
                || row.transaction.payee.localizedCaseInsensitiveContains(search)
            return matchFilter && matchSearch
        }
    }

    private var groupedItems: [(String, [ItemRow])] {
        let groups = Dictionary(grouping: filteredItems) { $0.categoryName }
        return groups
            .sorted { lhs, rhs in
                lhs.value.reduce(Decimal(0)) { $0 + (-$1.amount) }
                    > rhs.value.reduce(Decimal(0)) { $0 + (-$1.amount) }
            }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }
}

// MARK: - Row views

struct TransactionRow: View {
    let tx: Transaction
    var body: some View {
        HStack(spacing: 12) {
            Text(glyph).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.payee).font(.body)
                HStack(spacing: 4) {
                    if tx.splitItems.count > 1 {
                        Text("\(tx.splitItems.count) items")
                    } else if let cat = tx.category {
                        Text(cat.name)
                    }
                    if let acc = tx.account {
                        Text("· \(acc.name)")
                    }
                    if tx.paymentMethod != .unknown || tx.cardBrand != nil {
                        Image(systemName: tx.paymentMethod.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(tx.paymentDescription)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
        .padding(.vertical, 2)
    }

    private var glyph: String {
        if tx.splitItems.count > 1 { return "🧾" }
        return tx.category?.emoji ?? "🧾"
    }
}

private struct ItemRowView: View {
    let row: TransactionListView.ItemRow
    var body: some View {
        HStack {
            Text(row.categoryEmoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.description).font(.body).lineLimit(1)
                HStack(spacing: 4) {
                    Text(row.transaction.payee)
                    Text("· \(row.categoryName)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.string(for: row.amount, currency: row.currency))
                .font(.callout.monospacedDigit())
                .foregroundStyle(row.amount < 0 ? .red : .green)
        }
        .padding(.vertical, 2)
    }
}
