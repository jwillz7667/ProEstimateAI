import AuthenticationServices
import Foundation

/// Coordinates Sign in with Apple authorization flow and bridges the delegate-based
/// API to Swift concurrency via a `CheckedContinuation`.
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    // MARK: - Result type

    struct AppleSignInResult: Sendable {
        let identityToken: String
        let authorizationCode: String
        let fullName: String?
        let email: String?
    }

    // MARK: - Private state

    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    /// Atomically resume and clear the pending continuation. No-op if a
    /// previous delegate callback already completed it — prevents the runtime
    /// crash that `CheckedContinuation` raises when resumed twice.
    private func finish(with result: Result<AppleSignInResult, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
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
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
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
            email: credential.email
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
        // Return the first window scene's key window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
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
        case .system(let error):
            return error.localizedDescription
        }
    }
}
