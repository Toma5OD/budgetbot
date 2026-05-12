import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "dollarsign.circle.fill")
                .resizable()
                .frame(width: 96, height: 96)
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("BudgetBot")
                    .font(.largeTitle.bold())
                Text("Snap, scan or describe.\nThe AI does the bookkeeping.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                auth.handle(result, context: context)
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 50)
            .padding(.horizontal, 24)

            Text("Your data never leaves your device, except when sent to your chosen AI provider with your own key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .padding()
    }
}
