import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(FXService.self) private var fx
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var showAdd = false

    private var base: String {
        profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? "USD"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Net Worth") {
                    HStack {
                        Text("Total in \(base)")
                        Spacer()
                        Text(CurrencyFormatter.string(for: netWorthInBase, currency: base))
                            .monospacedDigit()
                            .foregroundStyle(netWorthInBase >= 0 ? Color.primary : Color.red)
                            .accessibilityLabel("Net worth \(CurrencyFormatter.string(for: netWorthInBase, currency: base))")
                    }
                    .font(.headline)
                }

                Section("Accounts") {
                    if accounts.isEmpty {
                        Text("No accounts yet — add a bank, savings, credit, or cash account to track money flowing in and out.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(accounts) { a in
                            NavigationLink(value: a) {
                                AccountRow(account: a, base: base, fx: fx)
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets { context.delete(accounts[idx]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityIdentifier("settings.link")
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add account")
                }
            }
            .navigationDestination(for: Account.self) { acc in
                AccountDetailView(account: acc)
            }
            .sheet(isPresented: $showAdd) {
                AddAccountView()
            }
        }
    }

    private var netWorthInBase: Decimal {
        accounts.filter { !$0.archived }.reduce(Decimal(0)) { acc, a in
            acc + fx.convert(a.balance, from: a.currency, to: base)
        }
    }
}

private struct AccountRow: View {
    let account: Account
    let base: String
    let fx: FXService

    var body: some View {
        HStack {
            Image(systemName: account.kind.systemImage)
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(account.name)
                Text("\(account.kind.displayName)\(account.institution.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.string(for: account.balance, currency: account.currency))
                    .monospacedDigit()
                if account.currency != base {
                    Text("≈ \(CurrencyFormatter.string(for: fx.convert(account.balance, from: account.currency, to: base), currency: base))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AddAccountView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: AccountKind = .bank
    @State private var institution = ""
    @State private var currency = "USD"
    @State private var openingBalanceText = "0"

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(AccountKind.allCases) { k in
                            Label(k.displayName, systemImage: k.systemImage).tag(k)
                        }
                    }
                    TextField("Institution (optional)", text: $institution)
                    TextField("Currency", text: $currency)
                        .textInputAutocapitalization(.characters)
                }
                Section("Opening balance") {
                    TextField("0.00", text: $openingBalanceText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let opening = Decimal(string: openingBalanceText) ?? 0
        let acc = Account(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            institution: institution.isEmpty ? nil : institution,
            currency: currency.uppercased(),
            openingBalance: opening
        )
        context.insert(acc)
        try? context.save()
        dismiss()
    }
}

struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("Account") {
                TextField("Name", text: $account.name)
                Picker("Kind", selection: Binding(
                    get: { account.kind },
                    set: { account.kind = $0 }
                )) {
                    ForEach(AccountKind.allCases) { Label($0.displayName, systemImage: $0.systemImage).tag($0) }
                }
                TextField("Institution", text: Binding(
                    get: { account.institution ?? "" },
                    set: { account.institution = $0.isEmpty ? nil : $0 }
                ))
            }
            Section("Balance") {
                HStack {
                    Text("Current")
                    Spacer()
                    Text(CurrencyFormatter.string(for: account.balance, currency: account.currency))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }
            }
            Section("Recent activity") {
                let recent = account.transactions
                    .sorted { $0.date > $1.date }
                    .prefix(20)
                if recent.isEmpty {
                    Text("No transactions yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recent)) { tx in
                        TransactionRow(tx: tx)
                    }
                }
            }
            Section {
                Toggle("Archived", isOn: $account.archived)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { try? context.save() }
            }
        }
    }
}
