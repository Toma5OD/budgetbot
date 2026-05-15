import SwiftUI
import SwiftData

/// Manage user dreams — names + prices the "What it could've been"
/// counterfactual engine compares against. Distinct from Savings
/// Goals (which actively track contributions); dreams are just
/// reference points.
struct DreamsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @Query(sort: \UserDream.createdAt, order: .reverse) private var dreams: [UserDream]
    @State private var showNew = false

    var body: some View {
        Group {
            if dreams.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(dreams) { d in
                            NavigationLink {
                                EditDreamSheet(dream: d)
                            } label: {
                                dreamRow(d)
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets { context.delete(dreams[idx]) }
                            try? context.save()
                        }
                    } footer: {
                        Text("Your dreams power the \"What it could've been\" cards on Analytics. The bigger the price gap between your dreams, the more variety you'll see.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("My dreams")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityIdentifier("dreams.add")
            }
        }
        .sheet(isPresented: $showNew) {
            NewDreamSheet()
        }
    }

    private func dreamRow(_ d: UserDream) -> some View {
        HStack(spacing: 12) {
            Text(d.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.body)
                Text(CurrencyFormatter.string(for: d.targetPrice, currency: d.currency))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if d.achievedAt != nil {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.current.incomeColor)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(theme.current.tint)
                .breathingPulse(amplitude: 0.04, period: 3.0)
            Text("Tell us what you want")
                .font(.title3.bold())
            Text("Engagement ring. House deposit. M3. Honeymoon. The app uses the prices to translate your spending into things you actually want.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showNew = true
            } label: {
                Label("Add your first dream", systemImage: "plus.circle.fill")
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

// MARK: - New / Edit

struct NewDreamSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var name: String = ""
    @State private var emoji: String = "🎯"
    @State private var priceText: String = ""
    @State private var currency: String = ""
    @State private var note: String = ""

    private let emojiOptions = [
        "🎯", "💍", "🏠", "🚗", "🏎", "✈️", "🍝", "🎓", "💻",
        "🎮", "⌚️", "📱", "💼", "🛩", "🎩", "💐", "🏝", "🪴"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Dream") {
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
                    TextField("Name (e.g. House deposit, BMW M3)", text: $name)
                    TextField("Price", text: $priceText)
                        .keyboardType(.decimalPad)
                }

                Section("Currency") {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currencies.supported) { c in
                            Text("\(c.code) — \(c.name)").tag(c.code)
                        }
                    }
                }

                Section("Note (optional)") {
                    TextField("Why this one?", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("New dream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                        .accessibilityIdentifier("dreams.create")
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
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Decimal(string: priceText.replacingOccurrences(of: ",", with: ".")) ?? 0 > 0
    }

    private func create() {
        guard let price = Decimal(string: priceText.replacingOccurrences(of: ",", with: ".")) else { return }
        let d = UserDream(
            name: name.trimmingCharacters(in: .whitespaces),
            emoji: emoji,
            targetPrice: price,
            currency: currency,
            note: note.isEmpty ? nil : note
        )
        context.insert(d)
        try? context.save()
        dismiss()
    }
}

struct EditDreamSheet: View {
    @Bindable var dream: UserDream
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var priceText: String = ""

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $dream.name)
                TextField("Emoji", text: $dream.emoji)
                TextField("Price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .onChange(of: priceText) { _, new in
                        if let d = Decimal(string: new.replacingOccurrences(of: ",", with: ".")) {
                            dream.targetPrice = d
                        }
                    }
            }
            Section {
                Toggle("Achieved", isOn: Binding(
                    get: { dream.achievedAt != nil },
                    set: { dream.achievedAt = $0 ? .now : nil }
                ))
            }
            Section {
                Button("Delete dream", role: .destructive) {
                    context.delete(dream)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Edit dream")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    try? context.save()
                    dismiss()
                }
            }
        }
        .onAppear { priceText = "\(dream.targetPrice)" }
    }
}
