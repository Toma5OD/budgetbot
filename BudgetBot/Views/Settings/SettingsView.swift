import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(FXService.self) private var fx
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var newKey: String = ""
    @State private var validating = false
    @State private var savedToast: String?
    @State private var saveError: String?
    @State private var showRemoveConfirm = false
    @State private var showAppleRevokeSheet = false

    static let availableModels: [(String, String)] = [
        ("claude-sonnet-4-6",          "Sonnet 4.6 · balanced (default)"),
        ("claude-opus-4-7",            "Opus 4.7 · highest quality"),
        ("claude-haiku-4-5-20251001",  "Haiku 4.5 · cheapest & fastest")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Name",  value: profiles.first?.displayName ?? "—")
                    LabeledContent("Email", value: profiles.first?.email ?? "—")
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                    }
                }

                Section("Currency") {
                    TextField("Default (used when adding tx)", text: Binding(
                        get: { profiles.first?.defaultCurrency ?? "USD" },
                        set: {
                            if let p = profiles.first { p.defaultCurrency = $0.uppercased() }
                            try? context.save()
                        }
                    ))
                    .textInputAutocapitalization(.characters)

                    TextField("Base (Net Worth & analytics)", text: Binding(
                        get: { profiles.first?.baseCurrency ?? "USD" },
                        set: {
                            if let p = profiles.first { p.baseCurrency = $0.uppercased() }
                            try? context.save()
                        }
                    ))
                    .textInputAutocapitalization(.characters)

                    HStack {
                        Text("FX rates")
                        Spacer()
                        if fx.isRefreshing {
                            ProgressView()
                        } else if let d = fx.fetchedAt {
                            Text(d, style: .relative).foregroundStyle(.secondary)
                        } else {
                            Text("Never").foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await fx.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh FX rates from ECB")
                    }
                }

                Section("Monthly budget") {
                    TextField("Optional", text: Binding(
                        get: { profiles.first?.monthlyBudget.map { "\($0)" } ?? "" },
                        set: { newVal in
                            guard let p = profiles.first else { return }
                            p.monthlyBudget = Decimal(string: newVal)
                            try? context.save()
                        }
                    ))
                    .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Model", selection: Binding(
                        get: { profiles.first?.aiModel ?? AIService.defaultModel },
                        set: {
                            if let p = profiles.first { p.aiModel = $0 }
                            try? context.save()
                        }
                    )) {
                        ForEach(Self.availableModels, id: \.0) { id, label in
                            Text(label).tag(id)
                        }
                    }
                } header: {
                    Text("AI model")
                } footer: {
                    Text("Costs and capability vary by model. Sonnet handles most receipts perfectly.")
                }

                Section {
                    SecureField("Paste a new key to replace", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        HStack {
                            if validating { ProgressView() }
                            Text(validating ? "Validating…" : "Validate & replace key")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || validating)

                    Button("Remove key", role: .destructive) {
                        showRemoveConfirm = true
                    }
                    if let e = saveError {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Stored in Keychain. Used only for requests to api.anthropic.com.")
                }

                if let savedToast {
                    Section { Text(savedToast).foregroundStyle(.green) }
                }

                Section {
                    NavigationLink {
                        DeleteAccountPreviewView(
                            onConfirm: {
                                deleteAccountAndData()
                                showAppleRevokeSheet = true
                            }
                        )
                    } label: {
                        Label("Delete account & all data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("settings.deleteAccount")
                } footer: {
                    Text("Wipes every transaction, account, recommendation, your API key and profile from this device. Cannot be undone.")
                }

                Section("Privacy") {
                    Link("Privacy & data policy",
                         destination: URL(string: "https://example.com/budgetbot/privacy")!)
                    Link("Where my data goes",
                         destination: URL(string: "https://example.com/budgetbot/data-flow")!)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Remove the API key?", isPresented: $showRemoveConfirm) {
                Button("Remove", role: .destructive) {
                    KeychainService.shared.delete(.anthropicAPIKey)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to paste it again before the AI can extract anything.")
            }
            .sheet(isPresented: $showAppleRevokeSheet) {
                AppleRevokeInstructionsSheet()
            }
        }
    }

    private func validateAndSave() async {
        saveError = nil
        validating = true
        defer { validating = false }
        let trimmed = newKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let ok = await AIService.validate(key: trimmed)
        guard ok else {
            saveError = "Key didn't authenticate against api.anthropic.com. Double-check and try again."
            return
        }
        try? KeychainService.shared.set(trimmed, for: .anthropicAPIKey)
        newKey = ""
        savedToast = "Key updated."
    }

    private func deleteAccountAndData() {
        // Wipe SwiftData
        for type: any PersistentModel.Type in [
            Transaction.self, Attachment.self, AIRecommendation.self,
            Account.self, TxCategory.self, UserProfile.self, FXRateSnapshot.self
        ] {
            try? context.delete(model: type)
        }
        try? context.save()

        // Wipe Keychain
        KeychainService.shared.delete(.anthropicAPIKey)
        KeychainService.shared.delete(.appleUserID)

        // Wipe pending captures from App Group
        PendingCaptureStore.clearAll()

        // Sign out
        auth.signOut()
    }
}

/// Apple Sign-In requires server-side token revocation to fully unlink the
/// account. We have no backend (see TODO.md), so we point the user at the
/// system-level revoke screen.
private struct AppleRevokeInstructionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Almost done.").font(.title2.bold())
                Text("Your data on this device is gone. To also revoke Sign in with Apple for BudgetBot:")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Open the Settings app", systemImage: "1.circle.fill")
                    Label("Tap your name → Sign-In & Security → Sign in with Apple", systemImage: "2.circle.fill")
                    Label("Find BudgetBot and tap Stop Using Apple ID", systemImage: "3.circle.fill")
                }
                .font(.callout)

                Spacer()
                Button {
                    if let url = URL(string: "App-prefs:") { UIApplication.shared.open(url) }
                    dismiss()
                } label: {
                    Text("Open Settings").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button("Done", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
