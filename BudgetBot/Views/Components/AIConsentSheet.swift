import SwiftUI

/// One-time disclosure + permission sheet shown before the first AI
/// action (receipt processing or an Ask question). Satisfies App
/// Review 5.1.2(i): states exactly what data is sent, names the
/// recipient, and obtains explicit permission before anything leaves
/// the device. Revocable later in Settings → AI.
struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called after the user taps "Allow" (consent is already recorded
    /// by then) — the caller resumes whatever action was gated.
    var onAllow: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    section(
                        icon: "doc.text.image",
                        title: "What gets sent",
                        body: "Only the content you submit for AI processing: receipt photos or PDFs you choose to process, any note text you attach, questions you type in Ask, and compact summaries of your transaction records when needed to answer a question."
                    )

                    section(
                        icon: "building.2",
                        title: "Who it goes to",
                        body: "Anthropic (api.anthropic.com), the AI provider — using your own API key. BudgetBot runs no servers and never sees your data. Anthropic processes it to return the extraction or answer, under their privacy policy."
                    )

                    section(
                        icon: "hand.raised",
                        title: "Your choice",
                        body: "Nothing is sent until you allow it. You can withdraw permission any time in Settings → AI — the AI features simply turn off; everything else keeps working."
                    )

                    Link("Read our privacy policy",
                         destination: URL(string: "https://toma5od.github.io/budgetbot/privacy/")!)
                        .font(.callout.bold())

                    buttons
                }
                .padding(20)
            }
            .navigationTitle("AI processing")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Before the AI sees anything")
                .font(.title2.bold())
            Text("BudgetBot's receipt extraction and Ask chat use a third-party AI service. Here's exactly what that means:")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func section(icon: String, title: String, body text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                AIConsent.grant()
                dismiss()
                onAllow()
            } label: {
                Text("Allow AI processing")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("aiconsent.allow")

            Button {
                dismiss()
            } label: {
                Text("Not now")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("aiconsent.deny")
        }
        .padding(.top, 6)
    }
}
