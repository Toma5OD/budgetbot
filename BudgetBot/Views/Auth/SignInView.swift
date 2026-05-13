import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    @State private var signingInGoogle = false

    var body: some View {
        ZStack {
            theme.current.background.view
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "creditcard.viewfinder")
                    .resizable().scaledToFit()
                    .frame(width: 110, height: 110)
                    .foregroundStyle(theme.current.tint)
                    .shadow(color: theme.current.tint.opacity(0.4), radius: 20)
                VStack(spacing: 8) {
                    Text("BudgetBot")
                        .font(theme.current.headingFont(.largeTitle))
                    Text("Snap, scan or describe.\nThe AI does the bookkeeping.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        auth.handle(result, context: context)
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 50)

                    Button {
                        signingInGoogle = true
                        Task {
                            await auth.signInWithGoogle(context: context)
                            signingInGoogle = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if signingInGoogle {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "g.circle.fill")
                                    .font(.title2)
                            }
                            Text(signingInGoogle ? "Opening Google…" : "Continue with Google")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.20, green: 0.45, blue: 0.95))
                        )
                    }
                    .disabled(signingInGoogle)
                }
                .padding(.horizontal, 24)

                if let err = auth.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Text("Your data never leaves your device, except when sent to your chosen AI provider with your own key. Sync (if enabled) goes via your iCloud account, end-to-end encrypted by Apple.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .padding()
        }
    }
}
