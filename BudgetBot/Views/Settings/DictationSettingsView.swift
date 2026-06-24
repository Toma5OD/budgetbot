import SwiftUI

/// Settings → Dictation. Lets the user choose how speech-to-text works
/// — on-device (default), or cloud Whisper / Gemini with their own key —
/// plus language, punctuation, and offline fallback.
struct DictationSettingsView: View {
    @State private var engine = DictationSettings.engine
    @State private var languageCode = DictationSettings.languageCode
    @State private var punctuation = DictationSettings.addsPunctuation
    @State private var offlineFallback = DictationSettings.offlineFallback
    @State private var cloudKey = ""
    @State private var savedNote: String?

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $engine) {
                    ForEach(DictationEngine.allCases) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: engine) { _, new in
                    DictationSettings.engine = new
                    loadKey()
                }
            } header: {
                Text("Engine")
            } footer: {
                Text(engine.blurb)
            }

            if engine.isCloud {
                Section {
                    SecureField("Paste \(engine.displayName) API key", text: $cloudKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button("Save key") { saveKey() }
                        .disabled(cloudKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let savedNote {
                        Text(savedNote).font(.caption).foregroundStyle(.green)
                    }
                } header: {
                    Text("\(engine.displayName) key")
                } footer: {
                    Text("Stored in the iOS Keychain. When you dictate, the recorded audio is sent to \(engine == .whisper ? "OpenAI" : "Google") using this key. Nothing is sent on the on-device engine.")
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
        .onAppear { loadKey() }
    }

    private func loadKey() {
        savedNote = nil
        if let k = engine.keychainKey {
            cloudKey = KeychainService.shared.get(k) ?? ""
        } else {
            cloudKey = ""
        }
    }

    private func saveKey() {
        guard let k = engine.keychainKey else { return }
        let trimmed = cloudKey.trimmingCharacters(in: .whitespaces)
        try? KeychainService.shared.set(trimmed, for: k)
        savedNote = "Saved."
    }
}
