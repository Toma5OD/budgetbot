import SwiftUI
import SwiftData

/// Bank-sync entry. Branches on whether the active provider has
/// credentials configured:
///   - Not configured → `GoCardlessSetupView` to paste API keys.
///   - Configured     → list of existing connections + an institution
///     picker for adding more.
struct ConnectBankView: View {
    @Environment(ThemeManager.self) private var theme

    @State private var refreshTick = UUID()

    private var provider: any BankSyncProvider { BankSyncRegistry.active }

    var body: some View {
        Group {
            if provider.isConfigured {
                ConfiguredBankView()
                    .id(refreshTick)
            } else if provider is GoCardlessBankSyncProvider {
                GoCardlessSetupView(onSaved: { refreshTick = UUID() })
            } else {
                // Stub providers — keep the old "coming soon" copy.
                stubFallback
            }
        }
        .navigationTitle("Bank sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stubFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.current.tint)
            Text("\(provider.displayName) — coming soon")
                .font(.title3.bold())
            Text("This provider isn't wired up yet. Switch the active provider to GoCardless in Settings to use bank sync today.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - GoCardless setup

/// First-time setup: explains the model, lets the user paste their
/// Secret ID + Secret Key, and validates by attempting a token
/// exchange before saving.
struct GoCardlessSetupView: View {
    let onSaved: () -> Void
    @Environment(ThemeManager.self) private var theme
    @State private var secretID: String = ""
    @State private var secretKey: String = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                steps
                form
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
                saveButton
                privacyNote
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "building.columns.fill")
                    .font(.title)
                    .foregroundStyle(theme.current.tint)
                Text("GoCardless Bank Account Data")
                    .font(.title3.bold())
                Spacer()
            }
            Text("BudgetBot uses GoCardless's free PSD2 tier for bank sync. Each user (you) gets their own free-tier account — that way one developer's quota can't be drained by every install of the app.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup (one-time, ~3 minutes)")
                .font(.subheadline.bold())
            stepRow(1, "Go to bankaccountdata.gocardless.com and sign up — it's free.")
            stepRow(2, "Under \"User Secrets\" create a new key pair. Copy the Secret ID and Secret Key.")
            stepRow(3, "Paste both below. We store them in Keychain and use them to read your account data on-device.")
        }
        .padding(14)
        .themedCard()
    }

    private func stepRow(_ n: Int, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 22, height: 22)
                .background(theme.current.tint.opacity(0.18), in: Circle())
                .foregroundStyle(theme.current.tint)
            Text(s)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Credentials").font(.subheadline.bold())
            TextField("Secret ID", text: $secretID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            SecureField("Secret Key", text: $secretKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var saveButton: some View {
        Button {
            Task { await saveAndValidate() }
        } label: {
            HStack {
                if saving { ProgressView().tint(.white) }
                Text(saving ? "Validating…" : "Save & connect")
                    .font(.callout.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.current.tint, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(secretID.isEmpty || secretKey.isEmpty || saving)
    }

    private var privacyNote: some View {
        Text("Your secrets stay on this device. BudgetBot makes API calls directly from your phone to GoCardless — there's no server in between.")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    @MainActor
    private func saveAndValidate() async {
        saving = true
        defer { saving = false }
        error = nil
        do {
            try KeychainService.shared.set(
                secretID.trimmingCharacters(in: .whitespacesAndNewlines),
                for: .goCardlessSecretID
            )
            try KeychainService.shared.set(
                secretKey.trimmingCharacters(in: .whitespacesAndNewlines),
                for: .goCardlessSecretKey
            )
            // Try a token exchange immediately — if it fails the
            // credentials are wrong, we clear them so the user can't
            // be stuck in a weird half-configured state.
            _ = try await GoCardlessAPI().institutions(country: "IE")
            onSaved()
        } catch {
            KeychainService.shared.delete(.goCardlessSecretID)
            KeychainService.shared.delete(.goCardlessSecretKey)
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Configured / connections list

/// Shown once credentials are set. Lists existing connections, lets
/// the user add a new one (picks institution → opens consent flow), and
/// triggers a manual sync.
struct ConfiguredBankView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @State private var connections: [BankConnection] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showInstitutionPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if connections.isEmpty && !loading {
                    emptyState
                } else if loading && connections.isEmpty {
                    ProgressView().padding(.top, 40)
                } else {
                    ForEach(connections) { c in
                        connectionCard(c)
                    }
                }
                Button {
                    showInstitutionPicker = true
                } label: {
                    Label("Connect another bank", systemImage: "plus.circle.fill")
                        .font(.callout.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.current.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showInstitutionPicker) {
            InstitutionPicker(onConnected: {
                Task { await reload() }
            })
        }
        .task { await reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "link.circle")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No banks connected").font(.headline)
            Text("Tap below to link your first account.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func connectionCard(_ c: BankConnection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(c.institution.displayName).font(.headline)
                Spacer()
                if c.needsReconnect {
                    Text("Reconnect needed")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                } else {
                    Text("Connected \(c.connectedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if c.needsReconnect {
                Text("Your bank's PSD2 consent expired. One tap re-runs the consent flow — no data is lost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(c.accounts) { acct in
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(theme.current.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(acct.displayName).font(.callout)
                            if let mask = acct.mask {
                                Text("•• \(mask)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let bal = acct.balance {
                            Text(CurrencyFormatter.string(for: bal, currency: acct.currency))
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            }
            HStack {
                if c.needsReconnect {
                    Button("Reconnect") {
                        Task { await reconnect(c) }
                    }
                    .font(.caption.bold())
                } else {
                    Button("Sync now") {
                        Task { await sync(connection: c) }
                    }
                    .font(.caption.bold())
                }
                Spacer()
                Button("Disconnect", role: .destructive) {
                    Task { await disconnect(c) }
                }
                .font(.caption.bold())
            }
        }
        .padding(14)
        .themedCard()
    }

    @MainActor
    private func reconnect(_ c: BankConnection) async {
        // Drop the old requisition (idempotent on the stub path; deletes
        // server-side on GoCardless) then create a fresh one for the
        // same institution. Local Account rows are matched on name, so
        // re-linking and re-syncing slot back into the same buckets.
        do {
            try await BankSyncRegistry.active.disconnect(c.id)
            _ = try await BankSyncRegistry.active.connect(institution: c.institution)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            connections = try await BankSyncRegistry.active.connections()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func sync(connection: BankConnection) async {
        let summary = await BankSyncService.syncConnection(connection, in: context)
        if let first = summary.errors.first { error = first }
    }

    @MainActor
    private func disconnect(_ c: BankConnection) async {
        do {
            try await BankSyncRegistry.active.disconnect(c.id)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Institution picker

struct InstitutionPicker: View {
    let onConnected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var country: String = "IE"
    @State private var institutions: [BankInstitution] = []
    @State private var loading = false
    @State private var error: String?
    @State private var connecting = false
    @State private var search: String = ""

    private let countries: [(code: String, name: String)] = [
        ("IE", "Ireland"), ("GB", "United Kingdom"), ("FR", "France"),
        ("DE", "Germany"), ("ES", "Spain"), ("IT", "Italy"),
        ("NL", "Netherlands"), ("BE", "Belgium"), ("PT", "Portugal")
    ]

    var body: some View {
        NavigationStack {
            Group {
                if loading && institutions.isEmpty {
                    ProgressView("Loading banks…")
                } else if let error {
                    VStack(spacing: 8) {
                        Text("Couldn't load banks").font(.headline)
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } else {
                    List {
                        Section {
                            Picker("Country", selection: $country) {
                                ForEach(countries, id: \.code) { c in
                                    Text(c.name).tag(c.code)
                                }
                            }
                            .onChange(of: country) { Task { await reload() } }
                        }
                        Section {
                            ForEach(filtered) { inst in
                                Button {
                                    Task { await connect(inst) }
                                } label: {
                                    HStack {
                                        Text(inst.displayName)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if connecting {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .disabled(connecting)
                            }
                        } header: {
                            Text("\(filtered.count) banks in \(country)")
                        }
                    }
                    .searchable(text: $search, prompt: "Filter banks")
                }
            }
            .navigationTitle("Pick your bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private var filtered: [BankInstitution] {
        guard !search.isEmpty else { return institutions }
        return institutions.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
        }
    }

    @MainActor
    private func reload() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            institutions = try await BankSyncRegistry.active.availableInstitutions(country: country)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func connect(_ inst: BankInstitution) async {
        connecting = true
        defer { connecting = false }
        do {
            _ = try await BankSyncRegistry.active.connect(institution: inst)
            onConnected()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
