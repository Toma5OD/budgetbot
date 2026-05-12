import SwiftUI
import SwiftData

/// Detailed preview of what "Delete account & all data" will erase, with
/// counts pulled live from SwiftData. Lets the user see exactly what gets
/// removed before they confirm. Required by Apple's account-deletion guideline
/// 5.1.1(v) — apps must surface this in-app, not just in a dialog.
struct DeleteAccountPreviewView: View {
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query private var recs: [AIRecommendation]
    @Query private var attachments: [Attachment]
    @Query private var profiles: [UserProfile]

    @State private var typedConfirm: String = ""
    @State private var confirming = false

    var body: some View {
        Form {
            Section {
                Text("You're about to delete:")
                    .font(.headline)
            }

            Section("Data on this device") {
                row("Transactions", transactions.count)
                row("Accounts", accounts.count)
                row("AI recommendations", recs.count)
                row("Receipt attachments", attachments.count)
                row("Your profile", profiles.count > 0 ? 1 : 0)
                row("Your Anthropic API key", KeychainService.shared.get(.anthropicAPIKey) != nil ? 1 : 0)
            }

            Section {
                Label("Sign in with Apple", systemImage: "applelogo")
                Text("This app has no backend, so we cannot call Apple's token-revoke endpoint for you. After you confirm, we'll show you how to revoke BudgetBot's Apple ID access from iOS Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What we can't delete for you")
            }

            Section {
                Text("Type **DELETE** to confirm.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("DELETE", text: $typedConfirm)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("delete.confirmField")
                Button(role: .destructive) {
                    confirming = true
                    onConfirm()
                    dismiss()
                } label: {
                    HStack {
                        if confirming { ProgressView() }
                        Text("Delete everything").frame(maxWidth: .infinity)
                    }
                }
                .disabled(typedConfirm.uppercased() != "DELETE" || confirming)
                .accessibilityIdentifier("delete.confirmButton")
            }
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
