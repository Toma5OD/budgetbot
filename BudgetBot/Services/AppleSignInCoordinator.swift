import SwiftUI
import AuthenticationServices
import UIKit

/// Bridges an `ASAuthorizationController` callback back to `AuthService`
/// and, critically, supplies an explicit presentation anchor.
///
/// Letting the system resolve the presentation context (as SwiftUI's
/// `SignInWithAppleButton` does) is unreliable when the app runs in
/// iPhone-compatibility mode on iPad or across multiple windows — the
/// auth sheet can fail to present. Returning the active foreground key
/// window fixes that.
final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }.first
            ?? UIWindow()
        return window
    }
}

/// The official `ASAuthorizationAppleIDButton`, wrapped for SwiftUI so
/// we get Apple's HIG-compliant button while triggering our own
/// controller-driven flow (see `AppleSignInCoordinator`).
struct AppleSignInButton: UIViewRepresentable {
    var style: ASAuthorizationAppleIDButton.Style
    var onTap: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: style
        )
        button.cornerRadius = 14
        button.addTarget(context.coordinator,
                         action: #selector(Coordinator.tapped),
                         for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        let onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func tapped() { onTap() }
    }
}
