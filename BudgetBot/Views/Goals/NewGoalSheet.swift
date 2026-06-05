import SwiftUI
import SwiftData

/// Create a new savings goal — name, emoji, target, optional deadline.
/// Renders as a sheet over the parent list.
struct NewGoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var name: String = ""
    @State private var emoji: String = "🎯"
    @State private var targetText: String = ""
    @State private var currency: String = ""
    @State private var deadline: Date = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var useDeadline: Bool = true
    @State private var note: String = ""
    @State private var rewardPackageID: String? = nil

    /// Curated picker — anything outside this list is still allowed via
    /// the Text field but these are the typical shapes a savings goal
    /// takes.
    private let emojiOptions = ["🎯", "✈️", "🏠", "🚗", "💍", "🎓", "💻", "🎮", "💪", "🎄", "👶", "🐶"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    HStack {
                        Text("Emoji")
                        Spacer()
                        Menu {
                            ForEach(emojiOptions, id: \.self) { e in
                                Button(e) { emoji = e }
                            }
                        } label: {
                            Text(emoji).font(.title2)
                        }
                    }
                    TextField("Name (e.g. Japan trip)", text: $name)
                    TextField("Target amount", text: $targetText)
                        .keyboardType(.decimalPad)
                }

                Section("Currency") {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currencies.supported) { c in
                            Text("\(c.code) — \(c.name)").tag(c.code)
                        }
                    }
                }

                Section {
                    Toggle("Has a deadline", isOn: $useDeadline)
                    if useDeadline {
                        DatePicker("Hit it by",
                                   selection: $deadline,
                                   in: Date()...,
                                   displayedComponents: .date)
                    }
                } footer: {
                    if useDeadline {
                        Text("We'll show you how much you need to set aside per day to hit the target.")
                    } else {
                        Text("No deadline — open-ended, progress only.")
                    }
                }

                Section {
                    Picker("Reward", selection: $rewardPackageID) {
                        Text("None").tag(String?.none)
                        ForEach(RewardCatalog.all) { pkg in
                            Label(pkg.displayName, systemImage: pkg.sfSymbol)
                                .tag(Optional(pkg.id))
                        }
                    }
                    if let id = rewardPackageID, let pkg = RewardCatalog.get(id: id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pkg.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(pkg.priceRange)
                                    .font(.caption.bold())
                                if pkg.containsAlcohol {
                                    Label("Contains alcohol", systemImage: "wineglass")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Finish-line reward")
                } footer: {
                    Text("Lock in your celebration up front. We'll send it when you hit the goal.")
                }

                Section("Notes") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("New goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                        .accessibilityIdentifier("goals.create")
                }
            }
            .onAppear {
                if currency.isEmpty {
                    currency = profiles.first?.baseCurrency
                        ?? profiles.first?.defaultCurrency
                        ?? Currencies.localeDefault
                }
            }
        }
    }

    private var canCreate: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && Decimal(string: cleaned(targetText)) ?? 0 > 0
    }

    private func cleaned(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ".")
    }

    private func create() {
        guard let target = Decimal(string: cleaned(targetText)) else { return }
        let goal = SavingsGoal(
            name: name.trimmingCharacters(in: .whitespaces),
            emoji: emoji,
            targetAmount: target,
            currency: currency,
            deadline: useDeadline ? deadline : nil,
            note: note.isEmpty ? nil : note,
            rewardPackageID: rewardPackageID
        )
        context.insert(goal)
        try? context.save()
        dismiss()
    }
}

// MARK: - Edit

struct EditGoalSheet: View {
    @Bindable var goal: SavingsGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var targetText: String = ""
    @State private var useDeadline: Bool = true
    @State private var deadlineDate: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name", text: $goal.name)
                    TextField("Target", text: $targetText)
                        .keyboardType(.decimalPad)
                        .onChange(of: targetText) { _, new in
                            if let d = Decimal(string: new.replacingOccurrences(of: ",", with: ".")) {
                                goal.targetAmount = d
                            }
                        }
                }
                Section {
                    Toggle("Has a deadline", isOn: $useDeadline)
                        .onChange(of: useDeadline) { _, on in
                            goal.deadline = on ? deadlineDate : nil
                        }
                    if useDeadline {
                        DatePicker("Hit it by", selection: $deadlineDate,
                                   in: Date()..., displayedComponents: .date)
                            .onChange(of: deadlineDate) { _, new in
                                goal.deadline = new
                            }
                    }
                }
                Section("Notes") {
                    TextField("Optional",
                              text: Binding(get: { goal.note ?? "" },
                                            set: { goal.note = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                targetText = "\(goal.targetAmount)"
                useDeadline = goal.deadline != nil
                deadlineDate = goal.deadline
                    ?? Calendar.current.date(byAdding: .month, value: 6, to: .now)
                    ?? .now
            }
        }
    }
}

// MARK: - Contribute

struct ContributionSheet: View {
    let goal: SavingsGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var date: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        Text(goal.currency).foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit())
                    }
                }
                Section("When") {
                    DatePicker("", selection: $date,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Section("Note") {
                    TextField("Optional — e.g. 'Birthday cash'", text: $note,
                              axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Contribute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("goals.contribute.save")
                }
            }
        }
    }

    private var canSave: Bool {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 > 0
    }

    private func save() {
        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else { return }
        let c = GoalContribution(
            amount: amount, date: date,
            note: note.isEmpty ? nil : note,
            goal: goal
        )
        context.insert(c)
        try? context.save()
        dismiss()
    }
}
