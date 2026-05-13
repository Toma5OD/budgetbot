import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var newKey: String = ""
    @State private var validating = false
    @State private var savedToast: String?
    @State private var saveError: String?
    @State private var showRemoveConfirm = false
    @State private var showAppleRevokeSheet = false

    private var initials: String {
        let name = profiles.first?.displayName ?? profiles.first?.email ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return chars.isEmpty ? String(name.prefix(1)).uppercased() : chars.joined()
    }

    static let availableModels: [(String, String)] = [
        ("claude-sonnet-4-6",          "Sonnet 4.6 · balanced (default)"),
        ("claude-opus-4-7",            "Opus 4.7 · highest quality"),
        ("claude-haiku-4-5-20251001",  "Haiku 4.5 · cheapest & fastest")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(.tint).frame(width: 36, height: 36)
                                Text(initials)
                                    .font(.callout.bold())
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading) {
                                Text(profiles.first?.displayName ?? "Profile")
                                    .font(.body)
                                if let email = profiles.first?.email {
                                    Text(email).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.profile")

                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                    }
                }

                Section {
                    Picker("Default", selection: Binding(
                        get: { profiles.first?.defaultCurrency ?? Currencies.localeDefault },
                        set: {
                            if let p = profiles.first { p.defaultCurrency = $0 }
                            try? context.save()
                        }
                    )) {
                        ForEach(Currencies.supported) { c in
                            Text(c.displayLabel).tag(c.code)
                        }
                    }
                    .accessibilityIdentifier("settings.defaultCurrency")

                    Picker("Base (Net Worth & analytics)", selection: Binding(
                        get: { profiles.first?.baseCurrency ?? Currencies.localeDefault },
                        set: {
                            if let p = profiles.first { p.baseCurrency = $0 }
                            try? context.save()
                        }
                    )) {
                        ForEach(Currencies.supported) { c in
                            Text(c.displayLabel).tag(c.code)
                        }
                    }
                    .accessibilityIdentifier("settings.baseCurrency")

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
                } header: {
                    Text("Currency")
                } footer: {
                    Text("Default is what new accounts use. Base is what Net Worth and analytics aggregate into. Receipt currencies are detected by the AI automatically.")
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
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        HStack {
                            Image(systemName: theme.current.systemImage)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text("Theme").font(.body)
                                Text(theme.current.displayName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.themeLink")
                } header: {
                    Text("Appearance")
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
            Split.self, Transaction.self, Attachment.self, AIRecommendation.self,
            Account.self, TxCategory.self, UserProfile.self, FXRateSnapshot.self,
            RecurringRule.self
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
