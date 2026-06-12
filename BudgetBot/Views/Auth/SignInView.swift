import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    @State private var signingInGoogle = false
    @State private var heroAppeared = false

    private let features: [(symbol: String, title: String, body: String)] = [
        ("camera.viewfinder", "Snap or scan anything",
         "Receipts, PDFs, bank screenshots — the AI extracts every line."),
        ("bolt.fill", "Categorised in seconds",
         "Mixed receipts are split per category automatically."),
        ("lock.shield.fill", "Your data, your key",
         "Stays on your device + iCloud. No servers we own touch your transactions.")
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.current.background.view
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: max(40, geo.size.height * 0.04))
                        brandHeader
                        Spacer(minLength: 16)
                        featureList
                        Spacer(minLength: 16)
                        signInButtons
                        legalFooter
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.7)) {
                heroAppeared = true
            }
            // Clear any "Google not configured" error left over from a
            // previous run — the button is now hidden, so the user
            // can't dismiss it any other way.
            if GoogleAuthConfig.clientID == nil {
                auth.lastError = nil
            }
        }
    }

    // MARK: - Brand

    private var brandHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.current.tint, theme.current.tint.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: theme.current.tint.opacity(0.45), radius: 22, y: 10)
                Image(systemName: "creditcard.viewfinder")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(heroAppeared ? 1.0 : 0.7)
            .opacity(heroAppeared ? 1.0 : 0.0)

            VStack(spacing: 6) {
                Text("BudgetBot")
                    .font(theme.current.headingFont(.largeTitle))
                Text("Snap, scan, describe.\nThe AI does your bookkeeping.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(heroAppeared ? 1.0 : 0.0)
            .offset(y: heroAppeared ? 0 : 12)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 14) {
            ForEach(Array(features.enumerated()), id: \.offset) { idx, f in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(theme.current.tint.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: f.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.current.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title).font(.subheadline.weight(.semibold))
                        Text(f.body).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .opacity(heroAppeared ? 1.0 : 0.0)
                .offset(y: heroAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.7, dampingFraction: 0.8)
                        .delay(0.1 + Double(idx) * 0.08),
                    value: heroAppeared
                )
            }
        }
    }

    // MARK: - Sign-in buttons (matched visual weight)

    private var signInButtons: some View {
        VStack(spacing: 12) {
            AppleSignInButton(style: scheme == .dark ? .white : .black) {
                auth.signInWithApple(context: context)
            }
            .frame(height: 54)
            .accessibilityLabel("Sign in with Apple")

            if GoogleAuthConfig.clientID != nil {
                Button {
                    signingInGoogle = true
                    Task {
                        await auth.signInWithGoogle(context: context)
                        signingInGoogle = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        if signingInGoogle {
                            ProgressView().tint(.primary)
                        } else {
                            GoogleGlyph()
                        }
                        Text(signingInGoogle ? "Opening Google…" : "Continue with Google")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(UIColor.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.pressable)
                .disabled(signingInGoogle)
                .accessibilityLabel("Continue with Google")
            }

            if let err = auth.lastError {
                Label(err, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Legal

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("By continuing you agree to our terms and privacy policy.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Google "G" glyph
// Google's brand asset isn't bundled — we render an approximation using the
// four brand colours so the button still reads as "Google" without licensing.

private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Image(systemName: "g.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96), // blue
                            Color(red: 0.92, green: 0.26, blue: 0.21), // red
                            Color(red: 0.98, green: 0.74, blue: 0.02), // yellow
                            Color(red: 0.20, green: 0.66, blue: 0.33)  // green
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 24, height: 24)
    }
}
