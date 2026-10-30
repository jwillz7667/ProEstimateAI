import AuthenticationServices
import Foundation

/// Coordinates Sign in with Apple authorization flow and bridges the delegate-based
/// API to Swift concurrency via a `CheckedContinuation`.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    // MARK: - Result type

    struct AppleSignInResult: Sendable {
        let identityToken: String
        let authorizationCode: String
        let fullName: String?
        let email: String?
        let rawNonce: String
    }

    // MARK: - Private state

    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var pendingNonce: String?
    private var pendingState: String?
    private var controller: ASAuthorizationController?

    /// Atomically resume and clear the pending continuation. No-op if a
    /// previous delegate callback already completed it — prevents the runtime
    /// crash that `CheckedContinuation` raises when resumed twice.
    private func finish(with result: Result<AppleSignInResult, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        pendingNonce = nil
        pendingState = nil
        controller = nil
        switch result {
        case .success(let value):
            cont.resume(returning: value)
        case .failure(let error):
            cont.resume(throwing: error)
        }
    }

    // MARK: - Public API

    /// Initiates the Sign in with Apple flow and returns the credential data.
    /// Throws if the user cancels or an error occurs.
    func signIn() async throws -> AppleSignInResult {
        guard continuation == nil else { throw AppleSignInError.requestInProgress }
        let rawNonce = try OAuthRequestSecurity.randomToken()
        let state = try OAuthRequestSecurity.randomToken()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.pendingNonce = rawNonce
            self.pendingState = state

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = OAuthRequestSecurity.nonceHash(rawNonce)
            request.state = state

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(AppleSignInError.invalidCredential))
            return
        }
        guard let rawNonce = pendingNonce, let state = pendingState, credential.state == state else {
            finish(with: .failure(AppleSignInError.stateMismatch))
            return
        }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            finish(with: .failure(AppleSignInError.missingIdentityToken))
            return
        }

        guard let authCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authCodeData, encoding: .utf8)
        else {
            finish(with: .failure(AppleSignInError.missingAuthorizationCode))
            return
        }

        // Combine name components if provided (only comes on first sign-in)
        var fullName: String?
        if let nameComponents = credential.fullName {
            let parts = [nameComponents.givenName, nameComponents.familyName]
                .compactMap { $0 }
            if !parts.isEmpty {
                fullName = parts.joined(separator: " ")
            }
        }

        let result = AppleSignInResult(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            email: credential.email,
            rawNonce: rawNonce
        )

        finish(with: .success(result))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let asError = error as? ASAuthorizationError,
           asError.code == .canceled
        {
            finish(with: .failure(AppleSignInError.cancelled))
        } else {
            finish(with: .failure(AppleSignInError.system(error)))
        }
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Errors

enum AppleSignInError: LocalizedError {
    case invalidCredential
    case missingIdentityToken
    case missingAuthorizationCode
    case cancelled
    case stateMismatch
    case requestInProgress
    case system(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple sign-in credential."
        case .missingIdentityToken:
            return "Could not retrieve identity token from Apple."
        case .missingAuthorizationCode:
            return "Could not retrieve authorization code from Apple."
        case .cancelled:
            return "Sign in with Apple was cancelled."
        case .stateMismatch:
            return "Apple sign-in failed a security check. Please try again."
        case .requestInProgress:
            return "Apple sign-in is already in progress."
        case .system(let error):
            return error.localizedDescription
        }
    }
}
