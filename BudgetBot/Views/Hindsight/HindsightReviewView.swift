import SwiftUI
import SwiftData

/// "Rate in hindsight" — a swipeable deck of past purchases the user
/// hasn't reviewed yet. The aim is two things at once:
///
/// 1. **Data**: every tap fills in `Transaction.hindsightRating` so the
///    analytics surface can compute things like "categories with the
///    lowest avg hindsight rating" — i.e. spend that *the user
///    themselves* labelled as not worth it. That's a far stronger
///    signal than category-level heuristics.
///
/// 2. **Game**: rating one purchase should feel fun, not like a chore.
///    Card flies off in the swipe direction with rotation; the next
///    card pops forward from the back of the stack; tapping a star
///    triggers a soft burst. Undo button lives in the toolbar so a
///    misclick costs nothing.
///
/// Swipe gestures map to extremes for fast triage:
///   - Swipe left = 1 star (regret it)
///   - Swipe right = 5 stars (worth every cent)
///   - Tap a star = exact rating
///   - Skip button leaves the rating nil (card just disappears)
struct HindsightReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @Query(
        filter: #Predicate<Transaction> {
            $0.confirmed && $0.hindsightRating == nil && $0.amount < 0
        },
        sort: \Transaction.date,
        order: .reverse
    )
    private var unrated: [Transaction]

    @State private var index = 0
    @State private var dragOffset: CGSize = .zero
    @State private var ratedThisSession = 0
    @State private var lastTransaction: Transaction?
    @State private var lastRating: Int?
    @State private var lastRatedAt: Date?
    @State private var burstAt: Int? = nil   // star count for burst animation
    @State private var skippedIDs: Set<UUID> = []

    private var deck: [Transaction] {
        unrated.filter { !skippedIDs.contains($0.id) }
    }

    var body: some View {
        ZStack {
            theme.current.background.view.ignoresSafeArea()
            content
        }
        .navigationTitle("In hindsight…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    undoLast()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(lastTransaction == nil)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if deck.isEmpty {
            emptyState
        } else {
            VStack(spacing: 20) {
                progressHeader
                deckView
                ratingBar
                skipButton
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Header

    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(ratedThisSession) rated this session")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(deck.count) to go")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            // Progress bar — total reviewed across all time vs total
            // expense transactions. Cheap motivator.
            ProgressView(value: progressFraction)
                .tint(theme.current.tint)
        }
        .padding(.horizontal, 20)
    }

    private var progressFraction: Double {
        let total = (try? context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.confirmed && $0.amount < 0 }
        )).count) ?? 0
        let unratedNow = deck.count
        let done = total - unratedNow
        return total == 0 ? 0 : Double(done) / Double(total)
    }

    // MARK: - Deck

    private var deckView: some View {
        ZStack {
            // Render up to 3 cards in the stack, top-most last so the
            // current card is interactive.
            ForEach(Array(deck.prefix(3).enumerated().reversed()), id: \.offset) { idx, tx in
                cardView(tx, depth: idx)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private func cardView(_ tx: Transaction, depth: Int) -> some View {
        let isTop = depth == 0
        let depthScale: CGFloat = 1 - CGFloat(depth) * 0.04
        let depthOffset: CGFloat = CGFloat(depth) * 10

        ReviewCard(tx: tx, theme: theme.current, burstAt: isTop ? burstAt : nil)
            .scaleEffect(isTop ? 1 : depthScale)
            .offset(y: isTop ? 0 : depthOffset)
            .offset(isTop ? dragOffset : .zero)
            .rotationEffect(.degrees(isTop ? Double(dragOffset.width / 18) : 0))
            .overlay(alignment: .topLeading) {
                if isTop, dragOffset.width < -40 {
                    swipeLabel(text: "REGRET", color: theme.current.expenseColor, leading: true)
                        .opacity(min(1, Double(-dragOffset.width / 120)))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isTop, dragOffset.width > 40 {
                    swipeLabel(text: "WORTH IT", color: theme.current.incomeColor, leading: false)
                        .opacity(min(1, Double(dragOffset.width / 120)))
                }
            }
            .shadow(color: .black.opacity(isTop ? 0.18 : 0.06),
                    radius: isTop ? 16 : 8,
                    x: 0, y: isTop ? 12 : 4)
            .zIndex(isTop ? 10 : Double(2 - depth))
            .gesture(
                isTop
                ? DragGesture()
                    .onChanged { v in dragOffset = v.translation }
                    .onEnded { v in handleSwipeEnd(tx: tx, translation: v.translation) }
                : nil
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: dragOffset)
    }

    private func swipeLabel(text: String, color: Color, leading: Bool) -> some View {
        Text(text)
            .font(.title.bold())
            .tracking(2)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(color)
            .rotationEffect(.degrees(leading ? -16 : 16))
            .padding(20)
    }

    // MARK: - Star rating bar

    private var ratingBar: some View {
        HStack(spacing: 14) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    guard let tx = deck.first else { return }
                    fire(star)
                    commit(rating: star, tx: tx)
                } label: {
                    Image(systemName: burstAt == star ? "star.fill" : "star")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(starColor(star))
                        .scaleEffect(burstAt == star ? 1.25 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: burstAt)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func starColor(_ star: Int) -> Color {
        // Cool→warm ramp: 1 star = red, 5 stars = green.
        switch star {
        case 1: return theme.current.expenseColor
        case 2: return .orange
        case 3: return .yellow
        case 4: return Color(red: 0.5, green: 0.8, blue: 0.3)
        default: return theme.current.incomeColor
        }
    }

    private var skipButton: some View {
        Button {
            guard let tx = deck.first else { return }
            withAnimation { skippedIDs.insert(tx.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "forward.fill")
                Text("Skip for now")
            }
            .font(.callout.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.current.incomeColor)
            Text("All caught up.")
                .font(.title3.bold())
            Text(ratedThisSession > 0
                 ? "Rated \(ratedThisSession) this session. Capture a few more receipts and come back."
                 : "Nothing left to rate right now. Capture a few receipts and come back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done", action: { dismiss() })
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Actions

    private func handleSwipeEnd(tx: Transaction, translation: CGSize) {
        let threshold: CGFloat = 110
        if translation.width < -threshold {
            commit(rating: 1, tx: tx)
        } else if translation.width > threshold {
            commit(rating: 5, tx: tx)
        } else if translation.height < -threshold {
            // Swipe up = skip without rating.
            withAnimation { skippedIDs.insert(tx.id) }
            dragOffset = .zero
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
        }
    }

    private func commit(rating: Int, tx: Transaction) {
        lastTransaction = tx
        lastRating = tx.hindsightRating
        lastRatedAt = tx.hindsightRatedAt
        tx.hindsightRating = rating
        tx.hindsightRatedAt = .now
        try? context.save()
        ratedThisSession += 1
        // Animate the card off in the direction of the rating: low → left,
        // high → right.
        let direction: CGFloat = rating >= 3 ? 600 : -600
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            dragOffset = CGSize(width: direction, height: 80)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            dragOffset = .zero
        }
    }

    private func fire(_ star: Int) {
        burstAt = star
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if burstAt == star { burstAt = nil }
        }
    }

    private func undoLast() {
        guard let tx = lastTransaction else { return }
        tx.hindsightRating = lastRating
        tx.hindsightRatedAt = lastRatedAt
        try? context.save()
        lastTransaction = nil
        lastRating = nil
        lastRatedAt = nil
        ratedThisSession = max(0, ratedThisSession - 1)
    }
}

// MARK: - Card

private struct ReviewCard: View {
    let tx: Transaction
    let theme: Theme
    /// Drives the star burst overlay on the card content.
    let burstAt: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tx.payee)
                    .font(.title2.bold())
                    .lineLimit(2)
                Spacer()
                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(CurrencyFormatter.string(for: tx.amount, currency: tx.currency))
                    .font(.system(size: 48, weight: .black,
                                  design: theme.numericDesign))
                    .foregroundStyle(theme.expenseColor)
                Spacer()
            }

            if let cat = tx.category {
                HStack(spacing: 6) {
                    Text(cat.emoji)
                    Text(cat.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            attachmentView
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )

            if let note = tx.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("Knowing what you know now — was it worth it?")
                .font(.caption)
                .italic()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.background.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(
            burstOverlay
        )
    }

    @ViewBuilder
    private var attachmentView: some View {
        if let att = tx.attachment {
            switch att.kind {
            case .image:
                if let data = att.data, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    placeholderTile("photo")
                }
            case .pdf:   placeholderTile("doc.richtext.fill")
            case .text:  placeholderTile("text.bubble.fill")
            }
        } else {
            placeholderTile("receipt")
        }
    }

    private func placeholderTile(_ icon: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.gray.opacity(0.16), Color.gray.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var burstOverlay: some View {
        if let star = burstAt {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) * .pi / 4
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            star <= 2 ? theme.expenseColor : theme.incomeColor
                        )
                        .offset(x: cos(angle) * 80, y: sin(angle) * 80)
                        .opacity(0.85)
                }
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}

private extension Theme.BackgroundStyle {
    /// Plausible card surface for the review deck. Frosted on dark
    /// themes via opacity, solid on light themes via the first colour.
    var cardSurface: Color {
        switch self {
        case .solid(let c): return c.opacity(0.92)
        case .linearGradient(let cs, _, _):
            return (cs.first ?? Color(UIColor.systemBackground)).opacity(0.88)
        }
    }
}
