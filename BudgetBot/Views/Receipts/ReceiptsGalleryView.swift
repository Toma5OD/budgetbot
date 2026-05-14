import SwiftUI
import SwiftData

/// Grid of every saved receipt image, groupable by month or by business.
/// Each tile is a thumbnail with a payee + amount badge; tap drills into
/// the underlying Transaction.
struct ReceiptsGalleryView: View {
    @Query(
        filter: #Predicate<Transaction> { $0.confirmed && $0.attachment != nil },
        sort: \Transaction.date,
        order: .reverse
    )
    private var transactions: [Transaction]

    @Binding var groupBy: GroupBy

    enum GroupBy: String, CaseIterable, Identifiable {
        case date = "By date"
        case business = "By business"
        var id: String { rawValue }
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if transactions.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: .sectionHeaders) {
                    ForEach(grouped, id: \.0) { groupName, rows in
                        Section {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(rows) { tx in
                                    NavigationLink(value: tx) {
                                        ReceiptThumbnail(tx: tx)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        } header: {
                            HStack {
                                Text(groupName)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(rows.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No saved receipts yet").font(.headline)
            Text("Captured photos and PDFs of receipts will show up here, grouped by month or by business.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Grouping

    private var grouped: [(String, [Transaction])] {
        switch groupBy {
        case .date:
            let df = DateFormatter(); df.dateFormat = "MMMM yyyy"
            let cal = Calendar.current
            let groups = Dictionary(grouping: transactions) { tx in
                cal.date(from: cal.dateComponents([.year, .month], from: tx.date)) ?? tx.date
            }
            return groups
                .sorted { $0.key > $1.key }
                .map { (df.string(from: $0.key), $0.value.sorted { $0.date > $1.date }) }
        case .business:
            let groups = Dictionary(grouping: transactions) { $0.payee }
            return groups
                .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
                .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        }
    }
}

private struct ReceiptThumbnail: View {
    let tx: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                thumbBackground
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(tx.amount < 0 ? .white : Color(red: 0.7, green: 1.0, blue: 0.8))
                    if tx.cardLast4 != nil || tx.paymentMethod == .cash {
                        Text(tx.paymentDescription)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(8)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(tx.payee)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var thumbBackground: some View {
        if let att = tx.attachment {
            switch att.kind {
            case .image:
                if let data = att.data, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholderTile(icon: "photo")
                }
            case .pdf:
                placeholderTile(icon: "doc.richtext.fill")
            case .text:
                placeholderTile(icon: "text.bubble.fill")
            }
        } else {
            placeholderTile(icon: "photo")
        }
    }

    private func placeholderTile(icon: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.gray.opacity(0.18), Color.gray.opacity(0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
        }
    }
}
