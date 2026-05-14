import SwiftUI
import SwiftData

/// Top-level Settings. Designed in the iOS Settings style: profile header
/// card at the top, then sectioned cards of icon-led rows. Danger zone
/// (sign out, delete) is isolated at the bottom.
struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(FXService.self) private var fx
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var showSignOutConfirm = false
    @State private var showRemoveKeyConfirm = false
    @State private var showAppleRevokeSheet = false
    @State private var showLoadDemoConfirm = false
    @State private var isLoadingDemo = false
    @State private var cloudKitToggle = PersistenceController.isCloudKitSyncEnabled
    @State private var showCloudKitRestartHint = false
    @State private var notifEnabled  = LocalNotificationService.shared.enabled
    @State private var notifWeekly   = LocalNotificationService.shared.weeklyRecapEnabled
    @State private var notifSubs     = LocalNotificationService.shared.subscriptionRenewalEnabled
    @State private var notifBudget   = LocalNotificationService.shared.budgetThresholdEnabled
    @State private var savedToast: String?

    static let availableModels: [(String, String)] = [
        ("claude-sonnet-4-6",          "Sonnet 4.6 · balanced"),
        ("claude-opus-4-7",            "Opus 4.7 · highest quality"),
        ("claude-haiku-4-5-20251001",  "Haiku 4.5 · cheapest & fastest")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                profileHeader

                section("Money") {
                    NavigationLink {
                        CurrencyPickerSheet(
                            title: "Default currency",
                            footer: "Used when adding accounts and capturing transactions.",
                            selection: Binding(
                                get: { profiles.first?.defaultCurrency ?? Currencies.localeDefault },
                                set: {
                                    profiles.first?.defaultCurrency = $0
                                    try? context.save()
                                }
                            )
                        )
                    } label: {
                        SettingsRow("Default currency",
                                    subtitle: Currencies.by(code: profiles.first?.defaultCurrency ?? "EUR")?.name,
                                    icon: "dollarsign.arrow.circlepath",
                                    tint: .blue) {
                            chevron(profiles.first?.defaultCurrency ?? "EUR")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.defaultCurrency")

                    RowDivider()

                    NavigationLink {
                        CurrencyPickerSheet(
                            title: "Base currency",
                            footer: "Net Worth and analytics roll up into this currency.",
                            selection: Binding(
                                get: { profiles.first?.baseCurrency ?? Currencies.localeDefault },
                                set: {
                                    profiles.first?.baseCurrency = $0
                                    try? context.save()
                                }
                            )
                        )
                    } label: {
                        SettingsRow("Base currency",
                                    subtitle: Currencies.by(code: profiles.first?.baseCurrency ?? "EUR")?.name,
                                    icon: "globe",
                                    tint: .teal) {
                            chevron(profiles.first?.baseCurrency ?? "EUR")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.baseCurrency")

                    RowDivider()

                    NavigationLink {
                        BudgetEditor(profile: profiles.first)
                    } label: {
                        SettingsRow("Monthly budget",
                                    subtitle: budgetSubtitle,
                                    icon: "chart.pie.fill",
                                    tint: .indigo) {
                            chevronOnly
                        }
                    }
                    .buttonStyle(.plain)

                    RowDivider()

                    Button {
                        Task { await fx.refresh() }
                    } label: {
                        SettingsRow("Exchange rates",
                                    subtitle: fxSubtitle,
                                    icon: "arrow.triangle.2.circlepath",
                                    tint: .green) {
                            if fx.isRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                section("AI") {
                    NavigationLink {
                        AIModelPickerSheet(
                            selection: Binding(
                                get: { profiles.first?.aiModel ?? AIService.defaultModel },
                                set: {
                                    profiles.first?.aiModel = $0
                                    try? context.save()
                                }
                            )
                        )
                    } label: {
                        SettingsRow("Model",
                                    subtitle: aiModelLabel,
                                    icon: "brain.head.profile",
                                    tint: .purple) {
                            chevronOnly
                        }
                    }
                    .buttonStyle(.plain)

                    RowDivider()

                    SettingsRow("YOLO mode",
                                subtitle: "Auto-accept everything the AI extracts",
                                icon: "bolt.fill",
                                tint: .yellow) {
                        Toggle("", isOn: Binding(
                            get: { profiles.first?.yoloMode ?? false },
                            set: {
                                profiles.first?.yoloMode = $0
                                try? context.save()
                            }
                        ))
                        .labelsHidden()
                    }
                    .accessibilityIdentifier("settings.yolo")

                    RowDivider()

                    SettingsRow("Critique pass",
                                subtitle: "A 2nd AI audits the 1st (costs 2× API)",
                                icon: "checkmark.seal.fill",
                                tint: .green) {
                        Toggle("", isOn: Binding(
                            get: { profiles.first?.critiqueMode ?? false },
                            set: {
                                profiles.first?.critiqueMode = $0
                                try? context.save()
                            }
                        ))
                        .labelsHidden()
                    }
                    .accessibilityIdentifier("settings.critique")

                    RowDivider()

                    NavigationLink {
                        APIKeyManagerView(savedToast: $savedToast,
                                          showRemoveConfirm: $showRemoveKeyConfirm)
                    } label: {
                        SettingsRow("API key",
                                    subtitle: KeychainService.shared.get(.anthropicAPIKey) == nil
                                        ? "Not set" : "Stored in Keychain",
                                    icon: "key.fill",
                                    tint: .orange) {
                            chevronOnly
                        }
                    }
                    .buttonStyle(.plain)
                }

                section("For fun") {
                    NavigationLink {
                        HallOfShameView()
                    } label: {
                        SettingsRow("Hall of Shame",
                                    subtitle: "Your stupidest purchases, ranked",
                                    icon: "trophy.fill",
                                    tint: .pink) {
                            chevronOnly
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.hallOfShame")

                    RowDivider()

                    NavigationLink {
                        HindsightReviewView()
                    } label: {
                        SettingsRow("Rate in hindsight",
                                    subtitle: "Score past purchases 1-5. The data tightens analytics; the swipe deck is the game.",
                                    icon: "star.leadinghalf.filled",
                                    tint: .yellow) {
                            chevronOnly
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.rateInHindsight")
                }

                section("Appearance") {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        SettingsRow("Theme",
                                    subtitle: theme.current.displayName,
                                    icon: theme.current.systemImage,
                                    tint: theme.current.tint) {
                            chevronOnly
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.themeLink")
                }

                section("Notifications") {
                    SettingsRow("Allow notifications",
                                subtitle: notifEnabled ? "Approved" : "Off",
                                icon: "bell.fill",
                                tint: .pink) {
                        Toggle("", isOn: $notifEnabled)
                            .labelsHidden()
                            .onChange(of: notifEnabled) { _, new in
                                Task {
                                    if new {
                                        let granted = await LocalNotificationService.shared.requestPermission()
                                        await MainActor.run {
                                            LocalNotificationService.shared.enabled = granted
                                            notifEnabled = granted
                                        }
                                    } else {
                                        LocalNotificationService.shared.enabled = false
                                    }
                                }
                            }
                    }
                    if notifEnabled {
                        RowDivider()
                        SettingsRow("Weekly recap",
                                    subtitle: "Sunday 6pm — how the week went",
                                    icon: "calendar",
                                    tint: .blue) {
                            Toggle("", isOn: $notifWeekly)
                                .labelsHidden()
                                .onChange(of: notifWeekly) { _, new in
                                    LocalNotificationService.shared.weeklyRecapEnabled = new
                                }
                        }
                        RowDivider()
                        SettingsRow("Subscription renewals",
                                    subtitle: "Heads-up the day before a known sub charges",
                                    icon: "arrow.triangle.2.circlepath",
                                    tint: .purple) {
                            Toggle("", isOn: $notifSubs)
                                .labelsHidden()
                                .onChange(of: notifSubs) { _, new in
                                    LocalNotificationService.shared.subscriptionRenewalEnabled = new
                                }
                        }
                        RowDivider()
                        SettingsRow("Budget threshold",
                                    subtitle: "Ping at 75% and 100% of the monthly budget",
                                    icon: "chart.pie.fill",
                                    tint: .orange) {
                            Toggle("", isOn: $notifBudget)
                                .labelsHidden()
                                .onChange(of: notifBudget) { _, new in
                                    LocalNotificationService.shared.budgetThresholdEnabled = new
                                }
                        }
                    }
                }

                section("Storage") {
                    SettingsRow("Sync to iCloud",
                                subtitle: cloudKitToggle
                                    ? "On — restart required after toggling"
                                    : "Off — data stays on this device",
                                icon: "icloud.fill",
                                tint: .blue) {
                        Toggle("", isOn: $cloudKitToggle)
                            .labelsHidden()
                            .onChange(of: cloudKitToggle) { _, new in
                                PersistenceController.setCloudKitSyncEnabled(new)
                                showCloudKitRestartHint = true
                            }
                    }
                    .accessibilityIdentifier("settings.cloudKitSync")
                }

                section("Privacy") {
                    Link(destination: URL(string: "https://example.com/budgetbot/privacy")!) {
                        SettingsRow("Privacy policy",
                                    icon: "hand.raised.fill",
                                    tint: .gray) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    RowDivider()

                    Link(destination: URL(string: "https://example.com/budgetbot/data-flow")!) {
                        SettingsRow("Where my data goes",
                                    icon: "network",
                                    tint: .gray) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                section("Developer (temp)") {
                    Button {
                        showLoadDemoConfirm = true
                    } label: {
                        SettingsRow("Load demo data",
                                    subtitle: isLoadingDemo
                                        ? "Wiping and reseeding…"
                                        : "Wipes everything, then loads a fake user for testing",
                                    icon: "sparkles.rectangle.stack.fill",
                                    tint: .pink) {
                            if isLoadingDemo {
                                ProgressView()
                            } else {
                                chevronOnly
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingDemo)
                    .accessibilityIdentifier("settings.loadDemoData")
                }

                section("Account") {
                    Button {
                        showSignOutConfirm = true
                    } label: {
                        SettingsRow("Sign out",
                                    icon: "rectangle.portrait.and.arrow.right",
                                    tint: .orange) { EmptyView() }
                    }
                    .buttonStyle(.plain)

                    RowDivider()

                    NavigationLink {
                        DeleteAccountPreviewView(onConfirm: {
                            deleteAccountAndData()
                            showAppleRevokeSheet = true
                        })
                    } label: {
                        SettingsRow("Delete account & all data",
                                    icon: "trash.fill",
                                    tint: .red) {
                            chevronOnly
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.deleteAccount")
                }

                if let savedToast {
                    Text(savedToast)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                }

                Text("Version 0.1.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in any time. Your data stays on this device.")
        }
        .confirmationDialog("Wipe everything and load demo data?",
                            isPresented: $showLoadDemoConfirm,
                            titleVisibility: .visible) {
            Button("Wipe & load demo", role: .destructive) {
                Task { await loadDemoData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes ALL of your existing accounts, transactions and categories, then inserts a fake demo user with ~3 months of synthetic activity. No way back.")
        }
        .sheet(isPresented: $showAppleRevokeSheet) {
            AppleRevokeInstructionsSheet()
        }
        .alert("Restart BudgetBot to apply", isPresented: $showCloudKitRestartHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iCloud sync \(cloudKitToggle ? "will start" : "will stop") on next launch. If iCloud sync stays disabled in dev, also make sure the container `iCloud.dev.toma5od.BudgetBot` exists in Xcode → Signing & Capabilities → iCloud.")
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        NavigationLink {
            ProfileView()
        } label: {
            HStack(spacing: 14) {
                AvatarCircle(initials: initials, size: 56, tint: theme.current.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profiles.first?.displayName ?? "Your profile")
                        .font(.title3.bold())
                    if let email = profiles.first?.email {
                        Text(email).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Edit your info, lifetime stats, and budget")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .themedCard()
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.profile")
    }

    // MARK: - Section wrapper

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .themedCard()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var chevronOnly: some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func chevron(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var initials: String {
        let name = profiles.first?.displayName ?? profiles.first?.email ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return chars.isEmpty ? String(name.prefix(1)).uppercased() : chars.joined()
    }

    private var budgetSubtitle: String? {
        guard let b = profiles.first?.monthlyBudget, b > 0 else { return "Not set" }
        let cur = profiles.first?.baseCurrency ?? "EUR"
        return CurrencyFormatter.string(for: b, currency: cur)
    }

    private var aiModelLabel: String? {
        let id = profiles.first?.aiModel ?? AIService.defaultModel
        return Self.availableModels.first { $0.0 == id }?.1 ?? id
    }

    private var fxSubtitle: String? {
        if fx.isRefreshing { return "Refreshing…" }
        if let d = fx.fetchedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Updated " + formatter.localizedString(for: d, relativeTo: .now)
        }
        return "Tap to fetch"
    }

    @MainActor
    private func loadDemoData() async {
        isLoadingDemo = true
        defer { isLoadingDemo = false }
        do {
            try DemoDataSeeder.wipeAndSeed(in: context)
            savedToast = "Demo data loaded."
        } catch {
            savedToast = "Failed to load demo data: \(error.localizedDescription)"
        }
    }

    private func deleteAccountAndData() {
        for type: any PersistentModel.Type in [
            Split.self, Transaction.self, Attachment.self, AIRecommendation.self,
            Account.self, TxCategory.self, UserProfile.self, FXRateSnapshot.self,
            RecurringRule.self
        ] {
            try? context.delete(model: type)
        }
        try? context.save()
        KeychainService.shared.delete(.anthropicAPIKey)
        KeychainService.shared.delete(.appleUserID)
        KeychainService.shared.delete(.googleUserID)
        PendingCaptureStore.clearAll()
        auth.signOut()
    }
}

// MARK: - Avatar

struct AvatarCircle: View {
    let initials: String
    var size: CGFloat = 56
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.35), radius: size / 5, y: size / 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Sub-screens

private struct CurrencyPickerSheet: View {
    let title: String
    let footer: String
    @Binding var selection: String

    var body: some View {
        List {
            Section {
                ForEach(Currencies.supported) { c in
                    Button {
                        selection = c.code
                    } label: {
                        HStack {
                            Text(c.symbol)
                                .font(.title3.bold())
                                .frame(width: 36)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(c.code).font(.body)
                                Text(c.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == c.code {
                                Image(systemName: "checkmark")
                                    .font(.callout.bold())
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            } footer: {
                Text(footer)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AIModelPickerSheet: View {
    @Binding var selection: String

    var body: some View {
        List {
            Section {
                ForEach(SettingsView.availableModels, id: \.0) { id, label in
                    Button {
                        selection = id
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(label).font(.body)
                                Text(id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == id {
                                Image(systemName: "checkmark")
                                    .font(.callout.bold())
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Sonnet handles most receipts perfectly and is the cheapest. Opus is overkill for everyday use.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("AI model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct APIKeyManagerView: View {
    @Binding var savedToast: String?
    @Binding var showRemoveConfirm: Bool
    @State private var newKey: String = ""
    @State private var validating = false
    @State private var saveError: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: KeychainService.shared.get(.anthropicAPIKey) == nil
                          ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(KeychainService.shared.get(.anthropicAPIKey) == nil ? .red : .green)
                    Text(KeychainService.shared.get(.anthropicAPIKey) == nil
                         ? "Not configured" : "Stored in iOS Keychain")
                    Spacer()
                }
            } footer: {
                Text("Used only for requests to api.anthropic.com. We never see it.")
            }

            Section {
                SecureField("sk-ant-…", text: $newKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button {
                    Task { await validateAndSave() }
                } label: {
                    HStack {
                        if validating { ProgressView() }
                        Text(validating ? "Validating…" : "Validate & save key")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || validating)
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Replace key")
            }

            Section {
                Button("Remove key", role: .destructive) {
                    showRemoveConfirm = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("API key")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove the API key?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                KeychainService.shared.delete(.anthropicAPIKey)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func validateAndSave() async {
        saveError = nil
        validating = true
        defer { validating = false }
        let trimmed = newKey.trimmingCharacters(in: .whitespaces)
        let ok = await AIService.validate(key: trimmed)
        guard ok else {
            saveError = "That key didn't authenticate. Double-check and try again."
            return
        }
        try? KeychainService.shared.set(trimmed, for: .anthropicAPIKey)
        newKey = ""
        savedToast = "Key saved."
    }
}

private struct BudgetEditor: View {
    let profile: UserProfile?
    @Environment(\.modelContext) private var context
    @State private var text: String = ""

    var body: some View {
        Form {
            Section {
                TextField("0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.title2.bold())
                    .onAppear {
                        text = profile?.monthlyBudget.map { "\($0)" } ?? ""
                    }
                    .onChange(of: text) { _, new in
                        profile?.monthlyBudget = Decimal(string: new)
                        try? context.save()
                    }
            } header: {
                Text("Amount per month (\(profile?.baseCurrency ?? "EUR"))")
            } footer: {
                Text("Used for the budget burndown in Analytics and your Profile.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Monthly budget")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
