import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Native Google sign-in via OAuth 2.0 Authorization Code flow with PKCE.
/// No GoogleSignIn SDK required — this implementation talks directly to
/// Google's endpoints and returns the signed ID token, which the iOS
/// `AuthService` posts to `POST /v1/auth/google-signin`.
///
/// Flow:
///   1. Generate a PKCE code verifier + S256 code challenge.
///   2. Open ASWebAuthenticationSession to Google's `/o/oauth2/v2/auth`.
///   3. Capture the redirect URL (scheme = reversed iOS Client ID).
///   4. Exchange the auth code for an ID token at
///      `https://oauth2.googleapis.com/token` (PKCE proves we
///      originated the request — no client secret needed for native
///      apps).
///   5. Decode email + name from the ID token's payload for UX use; the
///      backend re-verifies the signature and issuer.
struct GoogleSignInResult: Sendable {
    let identityToken: String
    let email: String?
    let fullName: String?
}

enum GoogleSignInError: Error, LocalizedError {
    case missingClientID
    case cancelled
    case stateMismatch
    case noAuthCode
    case tokenExchangeFailed(String)
    case invalidIDToken
    case system(Error)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google sign-in is not configured for this build (missing GIDClientID in Info.plist)."
        case .cancelled:
            return "Google sign-in was cancelled."
        case .stateMismatch:
            return "Google sign-in failed a security check. Please try again."
        case .noAuthCode:
            return "Google sign-in didn't return an authorization code."
        case let .tokenExchangeFailed(detail):
            return "Couldn't exchange the Google authorization code: \(detail)"
        case .invalidIDToken:
            return "Google returned an unreadable identity token."
        case let .system(err):
            return err.localizedDescription
        }
    }
}

@MainActor
final class GoogleSignInCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// iOS Client ID, read from Info.plist (`GIDClientID`).
    private let clientID: String
    private var session: ASWebAuthenticationSession?

    override init() {
        clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        super.init()
    }

    /// Run the full OAuth flow and return Google's signed ID token plus
    /// any profile fields embedded in the JWT payload.
    func signIn() async throws -> GoogleSignInResult {
        guard !clientID.isEmpty else {
            throw GoogleSignInError.missingClientID
        }

        // Reversed iOS Client ID is also the registered URL scheme. The
        // redirect URI Google expects is "<reversed>:/oauth/callback".
        let reversedClientID = clientID
            .components(separatedBy: ".")
            .reversed()
            .joined(separator: ".")
        let redirectURI = "\(reversedClientID):/oauth/callback"

        // PKCE pair — Google requires S256 challenges from native apps.
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomState()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let authURL = components.url else {
            throw GoogleSignInError.system(NSError(domain: "GoogleSignIn", code: -1))
        }

        let callbackURL = try await runWebAuthSession(authURL: authURL, callbackScheme: reversedClientID)

        // Verify state (mitigates CSRF), then extract auth code.
        let cbComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let returnedState = cbComponents?.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw GoogleSignInError.stateMismatch
        }
        guard let code = cbComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.noAuthCode
        }

        // Exchange code for an ID token.
        let tokens = try await exchangeCode(
            code: code,
            verifier: verifier,
            redirectURI: redirectURI
        )

        let claims = Self.decodeJWTPayload(tokens.idToken)
        return GoogleSignInResult(
            identityToken: tokens.idToken,
            email: claims["email"] as? String,
            fullName: claims["name"] as? String
        )
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Pin to the foreground key window. On iPad multi-window setups
        // we still get a sensible anchor because we always grab the
        // *active* foreground scene's window rather than the first scene.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        return scene?.windows.first(where: { $0.isKeyWindow })
            ?? scene?.windows.first
            ?? ASPresentationAnchor()
    }

    // MARK: - Web auth session bridge

    private func runWebAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let nsError = error as? NSError,
                   nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                   nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                {
                    cont.resume(throwing: GoogleSignInError.cancelled)
                    return
                }
                if let error {
                    cont.resume(throwing: GoogleSignInError.system(error))
                    return
                }
                guard let url else {
                    cont.resume(throwing: GoogleSignInError.system(NSError(domain: "GoogleSignIn", code: -1)))
                    return
                }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let id_token: String
        let access_token: String?
        var idToken: String {
            id_token
        }
    }

    private func exchangeCode(
        code: String,
        verifier: String,
        redirectURI: String
    ) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        request.httpBody = body
            .map { "\($0.key)=\(Self.percentEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw GoogleSignInError.tokenExchangeFailed(String(snippet))
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GoogleSignInError.invalidIDToken
        }
    }

    // MARK: - PKCE / state helpers

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Decode the middle segment of a JWT for UX-only use (e.g. pre-fill
    /// the user's display name on first sign-up). The backend
    /// re-verifies the JWT signature and audience — we never trust this
    /// payload for authorization.
    static func decodeJWTPayload(_ token: String) -> [String: Any] {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return [:] }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = base64.count % 4
        if pad > 0 { base64.append(String(repeating: "=", count: 4 - pad)) }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }
}

private extension Data {
    /// base64url (RFC 7636) — required by PKCE: no padding, `-` and `_`
    /// instead of `+` and `/`.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
