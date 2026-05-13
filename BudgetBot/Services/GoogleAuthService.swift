import Foundation
import AuthenticationServices
import UIKit

/// "Continue with Google" via Google's OAuth 2.0 endpoint, backed by
/// `ASWebAuthenticationSession`. No third-party SDK — we own the four screens
/// of complexity (open URL, parse callback, exchange code, fetch profile).
///
/// Setup the user has to do once (documented in PRIVACY.md / SOLID.md):
///   1. Google Cloud Console → APIs & Services → Credentials.
///   2. Create OAuth client ID, type **iOS**.
///   3. Bundle ID = `dev.toma5od.BudgetBot`.
///   4. Copy the *Client ID* into `GoogleAuthConfig.clientID`.
///   5. The reversed-client-ID URL scheme is registered in Info.plist via
///      `project.yml`.
///
/// Production keeps the client ID in code — Google iOS clients are public by
/// design (Google explicitly allows ID + reversed-scheme to ship in the binary;
/// no client secret is involved for the iOS flow).
enum GoogleAuthConfig {
    /// Paste your Google iOS OAuth client ID here. Until you do, the Google
    /// button surfaces a friendly "not configured" error rather than crashing.
    /// Format: `<digits>-<gibberish>.apps.googleusercontent.com`.
    static let clientID: String? = nil

    /// Derived from the client ID — Google calls it the "reversed client ID".
    /// e.g. clientID `123-abc.apps.googleusercontent.com` →
    /// reverseScheme  `com.googleusercontent.apps.123-abc`.
    static var reverseScheme: String? {
        guard let id = clientID,
              let prefix = id.components(separatedBy: ".apps.googleusercontent.com").first
        else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }

    /// PKCE-friendly scopes for identity only.
    static let scopes = ["openid", "email", "profile"]
}

struct GoogleProfile: Hashable, Sendable {
    let sub: String          // Google's stable user ID
    let email: String?
    let name: String?
    let pictureURL: URL?
}

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case userCancelled
    case noCallbackURL
    case noAuthCode(query: String?)
    case tokenExchangeFailed(String)
    case userinfoFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "Google Sign-In isn't configured yet. Add a client ID in Settings/source."
        case .userCancelled:           return "Sign-in cancelled."
        case .noCallbackURL:           return "Google didn't return a callback URL."
        case .noAuthCode(let q):       return "No authorisation code in callback. Query: \(q ?? "(none)")"
        case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
        case .userinfoFailed(let m):   return "User info fetch failed: \(m)"
        }
    }
}

@MainActor
final class GoogleAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {

    func signIn() async throws -> GoogleProfile {
        guard let clientID = GoogleAuthConfig.clientID,
              let scheme = GoogleAuthConfig.reverseScheme else {
            throw GoogleAuthError.notConfigured
        }

        // PKCE
        let codeVerifier = Self.randomURLSafeString(length: 64)
        let codeChallenge = Self.codeChallenge(for: codeVerifier)

        let state = Self.randomURLSafeString(length: 24)
        let callbackURL = "\(scheme):/oauth2redirect/google"

        var authURL = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        authURL.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: callbackURL),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GoogleAuthConfig.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256")
        ]

        // 1. Launch the browser auth session and collect the redirect.
        let returnedURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authURL.url!,
                callbackURLScheme: scheme
            ) { url, err in
                if let err = err as? ASWebAuthenticationSessionError, err.code == .canceledLogin {
                    cont.resume(throwing: GoogleAuthError.userCancelled); return
                }
                if let err { cont.resume(throwing: err); return }
                guard let url else { cont.resume(throwing: GoogleAuthError.noCallbackURL); return }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        // 2. Pull the auth code out of the callback.
        let comps = URLComponents(url: returnedURL, resolvingAgainstBaseURL: false)
        guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.noAuthCode(query: comps?.percentEncodedQuery)
        }
        let returnedState = comps?.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw GoogleAuthError.noAuthCode(query: "state mismatch")
        }

        // 3. Exchange code for access token.
        let token = try await exchange(code: code, verifier: codeVerifier,
                                       clientID: clientID, redirectURI: callbackURL)

        // 4. Fetch user info.
        return try await fetchUserinfo(accessToken: token)
    }

    // MARK: - Internals

    private func exchange(
        code: String, verifier: String, clientID: String, redirectURI: String
    ) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ].map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            throw GoogleAuthError.tokenExchangeFailed(msg)
        }
        struct TokenResp: Decodable { let access_token: String }
        let parsed = try JSONDecoder().decode(TokenResp.self, from: data)
        return parsed.access_token
    }

    private func fetchUserinfo(accessToken: String) async throws -> GoogleProfile {
        var req = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            throw GoogleAuthError.userinfoFailed(msg)
        }
        struct Info: Decodable {
            let sub: String
            let email: String?
            let name: String?
            let picture: String?
        }
        let parsed = try JSONDecoder().decode(Info.self, from: data)
        return GoogleProfile(
            sub: parsed.sub,
            email: parsed.email,
            name: parsed.name,
            pictureURL: parsed.picture.flatMap { URL(string: $0) }
        )
    }

    // MARK: - Helpers

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    static func randomURLSafeString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    static func codeChallenge(for verifier: String) -> String {
        // S256 = base64url(sha256(verifier))
        let data = Data(verifier.utf8)
        return Data(SHA256.hash(data: data)).base64URLEncodedString()
    }

    // ASWebAuthenticationPresentationContextProviding
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Always pick the foreground key window.
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

// MARK: - Crypto + base64url helpers

import CryptoKit

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
