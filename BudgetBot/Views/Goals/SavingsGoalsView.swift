import SwiftUI
import SwiftData

/// List of all savings goals. Each row is a card showing a progress
/// ring, current vs target, and the deadline / pace pill. Tap to
/// drill into the detail. "+" toolbar button adds a new goal.
struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @Query(sort: \SavingsGoal.createdAt, order: .reverse) private var goals: [SavingsGoal]

    @State private var showNew = false

    var body: some View {
        Group {
            if goals.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(goals) { goal in
                            NavigationLink(value: goal) {
                                GoalRowCard(goal: goal, theme: theme.current)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Savings goals")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add savings goal")
                .accessibilityIdentifier("goals.add")
            }
        }
        .navigationDestination(for: SavingsGoal.self) { goal in
            GoalDetailView(goal: goal)
        }
        .sheet(isPresented: $showNew) {
            NewGoalSheet()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 56))
                .foregroundStyle(theme.current.tint)
                .breathingPulse(amplitude: 0.04, period: 3.2)
            Text("No goals yet").font(.title3.bold())
            Text("Set a target, log contributions, watch the ring fill. Use it for trips, deposits, a new bike — anything bigger than next week's groceries.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showNew = true
            } label: {
                Label("Create your first goal", systemImage: "plus.circle.fill")
                    .font(.callout.bold())
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(theme.current.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(theme.current.tint)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 30)
    }
}

// MARK: - Row card

struct GoalRowCard: View {
    let goal: SavingsGoal
    let theme: Theme

    var body: some View {
        HStack(spacing: 14) {
            GoalProgressRing(progress: goal.progress,
                             tint: ringTint,
                             size: 70,
                             lineWidth: 8) {
                Text(goal.emoji).font(.title2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(goal.name).font(.headline)
                HStack(spacing: 6) {
                    Text(CurrencyFormatter.string(for: goal.currentAmount, currency: goal.currency))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("of \(CurrencyFormatter.string(for: goal.targetAmount, currency: goal.currency))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                pacePill
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14)
        .themedCard()
    }

    @ViewBuilder
    private var pacePill: some View {
        switch goal.pace {
        case .ahead:
            label("Ahead of pace", systemImage: "checkmark.circle.fill",
                  tint: theme.incomeColor)
        case .onTrack:
            label("On track", systemImage: "circle.fill", tint: .blue)
        case .behind:
            label("Behind pace", systemImage: "exclamationmark.circle.fill",
                  tint: .orange)
        case .impossible:
            label("Won't hit", systemImage: "xmark.circle.fill",
                  tint: theme.expenseColor)
        case .noDeadline:
            if let days = goal.daysRemaining {
                label("\(days)d left", systemImage: "clock.fill", tint: .gray)
            } else if goal.isHit {
                label("Done!", systemImage: "checkmark.seal.fill",
                      tint: theme.incomeColor)
            } else {
                label("No deadline", systemImage: "infinity", tint: .gray)
            }
        }
    }

    private func label(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var ringTint: Color {
        if goal.isHit { return theme.incomeColor }
        switch goal.pace {
        case .ahead:      return theme.incomeColor
        case .onTrack:    return .blue
        case .behind:     return .orange
        case .impossible: return theme.expenseColor
        case .noDeadline: return theme.tint
        }
    }
}

// MARK: - Reusable progress ring

struct GoalProgressRing<Content: View>: View {
    let progress: Double
    let tint: Color
    let size: CGFloat
    let lineWidth: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(
                    AngularGradient(colors: [tint, tint.opacity(0.6)], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            content()
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) {
                animated = progress
            }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                animated = new
            }
        }
    }
}
