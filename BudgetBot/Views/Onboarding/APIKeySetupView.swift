import SwiftUI

struct APIKeySetupView: View {
    var onSaved: () -> Void

    @State private var key: String = ""
    @State private var error: String?
    @State private var validating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-...", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Anthropic API key")
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Get one at console.anthropic.com. Stored in the iOS Keychain. BudgetBot only sends data to api.anthropic.com using this key — nowhere else.")
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        HStack {
                            if validating { ProgressView() }
                            Text(validating ? "Validating…" : "Validate & continue")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || validating)
                    .accessibilityHint("Pings api.anthropic.com to confirm the key works before saving")
                }
            }
            .navigationTitle("Connect AI")
        }
    }

    private func validateAndSave() async {
        error = nil
        validating = true
        defer { validating = false }
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        let ok = await AIService.validate(key: trimmed)
        guard ok else {
            error = "That key didn't authenticate against api.anthropic.com. Double-check and try again."
            return
        }
        do {
            try KeychainService.shared.set(trimmed, for: .anthropicAPIKey)
            onSaved()
        } catch {
            self.error = "Couldn't store key: \(error.localizedDescription)"
        }
    }
}
