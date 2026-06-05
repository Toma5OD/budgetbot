import SwiftUI
import SwiftData

/// Detail view for one goal. Big progress ring at the top, contribution
/// log below, "+ Contribute" floating button. Edit / delete via toolbar.
struct GoalDetailView: View {
    @Bindable var goal: SavingsGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var showContribute = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showClaimAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                rewardCard
                statsRow
                contributionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEdit = true
                    } label: { Label("Edit goal", systemImage: "pencil") }
                    if !goal.isHit, goal.completedAt == nil {
                        Button {
                            goal.completedAt = .now
                            try? context.save()
                        } label: { Label("Mark complete", systemImage: "checkmark.circle") }
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: { Label("Delete goal", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showContribute) {
            ContributionSheet(goal: goal)
        }
        .sheet(isPresented: $showEdit) {
            EditGoalSheet(goal: goal)
        }
        .confirmationDialog("Delete this goal?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete goal & contributions", role: .destructive) {
                context.delete(goal)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the goal and every contribution logged against it. Can't be undone.")
        }
        .alert("Reward delivery launches soon", isPresented: $showClaimAlert) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("We're lining up a gifting partner so your reward ships automatically. You'll hear from us when it's ready.")
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showContribute = true
            } label: {
                Label("Contribute", systemImage: "plus.circle.fill")
                    .font(.callout.bold())
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [theme.current.tint, theme.current.tint.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .shadow(color: theme.current.tint.opacity(0.4), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            GoalProgressRing(progress: goal.progress,
                             tint: ringTint,
                             size: 200,
                             lineWidth: 16) {
                VStack(spacing: 2) {
                    Text(goal.emoji).font(.system(size: 38))
                    Text("\(Int((goal.progress * 100).rounded()))%")
                        .font(.title2.bold().monospacedDigit())
                }
            }
            Text(CurrencyFormatter.string(for: goal.currentAmount, currency: goal.currency))
                .font(.system(size: 32, weight: .black, design: theme.current.numericDesign))
                .foregroundStyle(.primary)
            Text("of \(CurrencyFormatter.string(for: goal.targetAmount, currency: goal.currency))")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let note = goal.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .themedCard()
    }

    private var ringTint: Color {
        if goal.isHit { return theme.current.incomeColor }
        switch goal.pace {
        case .ahead:      return theme.current.incomeColor
        case .onTrack:    return .blue
        case .behind:     return .orange
        case .impossible: return theme.current.expenseColor
        case .noDeadline: return theme.current.tint
        }
    }

    // MARK: - Reward

    @ViewBuilder
    private var rewardCard: some View {
        if let id = goal.rewardPackageID, let pkg = RewardCatalog.get(id: id) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: pkg.sfSymbol)
                        .font(.title2)
                        .foregroundStyle(theme.current.tint)
                        .frame(width: 40, height: 40)
                        .background(theme.current.tint.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Finish-line reward")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(pkg.displayName).font(.headline)
                    }
                    Spacer()
                }
                Text(pkg.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if goal.isHit {
                    Button {
                        showClaimAlert = true
                    } label: {
                        Label("Claim reward", systemImage: "gift.fill")
                            .font(.callout.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(theme.current.tint, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Sent when you hit \(CurrencyFormatter.string(for: goal.targetAmount, currency: goal.currency)).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .themedCard()
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(title: "Remaining",
                     value: CurrencyFormatter.string(for: goal.remaining, currency: goal.currency))
            if let days = goal.daysRemaining {
                statTile(title: "Days left", value: "\(days)")
            }
            if let perDay = goal.requiredPerDay {
                statTile(title: "Per day",
                         value: CurrencyFormatter.string(for: perDay, currency: goal.currency))
            }
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .themedCard()
    }

    // MARK: - Contributions

    private var contributionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Contributions").font(.headline)
                Spacer()
                Text("\(goal.contributionsList.count)").font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if goal.contributionsList.isEmpty {
                Text("No contributions yet — tap **Contribute** to log one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.thinMaterial,
                                in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    let sorted = goal.contributionsList.sorted { $0.date > $1.date }
                    ForEach(sorted) { c in
                        contributionRow(c)
                        if c.id != sorted.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .themedCard()
            }
        }
    }

    private func contributionRow(_ c: GoalContribution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(CurrencyFormatter.string(for: c.amount, currency: goal.currency))
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(theme.current.incomeColor)
                Text(c.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let note = c.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button(role: .destructive) {
                context.delete(c)
                try? context.save()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}
