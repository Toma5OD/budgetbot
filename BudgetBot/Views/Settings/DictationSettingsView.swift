import SwiftUI

/// Settings → Voice & dictation. Chooses how speech-to-text works
/// — on-device (default), or cloud Whisper / Gemini — plus language,
/// punctuation and offline fallback. API keys are NOT entered here: they
/// all live in Settings → API keys. This screen only points at the one
/// the chosen engine needs.
struct DictationSettingsView: View {
    @State private var engine = DictationSettings.engine
    @State private var languageCode = DictationSettings.languageCode
    @State private var punctuation = DictationSettings.addsPunctuation
    @State private var offlineFallback = DictationSettings.offlineFallback

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $engine) {
                    ForEach(DictationEngine.allCases) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: engine) { _, new in DictationSettings.engine = new }
            } header: {
                Text("Engine")
            } footer: {
                Text("\(engine.blurb)\n\nFor voice we recommend OpenAI Whisper — it's the most accurate, and Anthropic has no speech model. On-device is free, private and works offline.")
            }

            if engine.isCloud {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: keyIsSet ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(keyIsSet ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(keyIsSet ? "\(engine.providerName) key is set"
                                          : "\(engine.providerName) key needed")
                                .font(.subheadline.weight(.medium))
                            Text(keyIsSet ? "Voice will use it. Manage it with your other keys."
                                          : "Add your \(engine.providerName) key to use this engine.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    NavigationLink {
                        APIKeyManagerView()
                    } label: {
                        Label(keyIsSet ? "Open API keys" : "Add key in API keys",
                              systemImage: "key.fill")
                    }
                } header: {
                    Text("\(engine.providerName) key")
                } footer: {
                    Text("All your API keys live in one place — Settings → API keys. Nothing is sent on the on-device engine.")
                }
            }

            Section("Language") {
                Picker("Recognition language", selection: $languageCode) {
                    ForEach(DictationSettings.languageOptions, id: \.code) { opt in
                        Text(opt.label).tag(opt.code)
                    }
                }
                .onChange(of: languageCode) { _, new in DictationSettings.languageCode = new }
            }

            Section {
                Toggle("Add punctuation", isOn: $punctuation)
                    .onChange(of: punctuation) { _, new in DictationSettings.addsPunctuation = new }
                    .disabled(engine.isCloud)
                Toggle("Use on-device when offline", isOn: $offlineFallback)
                    .onChange(of: offlineFallback) { _, new in DictationSettings.offlineFallback = new }
                    .disabled(!engine.isCloud)
            } header: {
                Text("Options")
            } footer: {
                Text("Punctuation applies to the on-device engine. Offline fallback uses on-device when a cloud engine can't reach the network.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Whether the chosen cloud engine's key is present in the Keychain.
    /// Read inline so it refreshes when returning from the API keys screen.
    private var keyIsSet: Bool {
        engine.keychainKey.flatMap { KeychainService.shared.get($0) }?.isEmpty == false
    }
}
