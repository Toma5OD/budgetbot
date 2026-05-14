import SwiftUI
import SwiftData

/// Bottom-sheet style notification center. Renders the items prepared by
/// `NotificationStore.rebuild`. Tap an item to act on it (open Capture,
/// dismiss the underlying object, etc).
struct NotificationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Environment(NotificationStore.self) private var store
    @Environment(FXService.self) private var fx
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var showReviewQueue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.items.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            NotificationRow(item: item, theme: theme.current) {
                                handle(item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                rebuild()
                store.markAllRead()
            }
            .sheet(isPresented: $showReviewQueue) {
                ReviewQueueView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("You're all caught up").font(.headline)
            Text("Nothing to act on right now. We'll surface budget alerts, new subscriptions, AI nudges and shared captures here when there are any.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 80)
    }

    private func handle(_ item: AppNotification) {
        switch item.kind {
        case .pendingCapture:
            dismiss()
        case .awaitingReview:
            showReviewQueue = true
        case .subscriptionDetected, .budgetThreshold:
            dismiss()
        case .aiRecommendation(let id):
            // Mark this rec as dismissed.
            let descriptor = FetchDescriptor<AIRecommendation>(
                predicate: #Predicate { $0.id == id }
            )
            if let rec = (try? context.fetch(descriptor))?.first {
                rec.dismissed = true
                try? context.save()
                rebuild()
            }
        }
    }

    private func rebuild() {
        store.rebuild(
            context: context,
            baseCurrency: profiles.first?.baseCurrency ?? Currencies.localeDefault,
            monthlyBudget: profiles.first?.monthlyBudget
        )
    }
}

private struct NotificationRow: View {
    let item: AppNotification
    let theme: Theme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint(for: item.kind))
                        .frame(width: 38, height: 38)
                    Image(systemName: item.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.title).font(.subheadline.bold())
                        Spacer()
                        Text(item.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(item.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
        }
        .buttonStyle(.pressable)
    }

    private func tint(for kind: AppNotification.Kind) -> Color {
        switch kind {
        case .pendingCapture:        .blue
        case .awaitingReview:        theme.tint
        case .subscriptionDetected:  .purple
        case .budgetThreshold:       .orange
        case .aiRecommendation:      theme.incomeColor
        }
    }
}
