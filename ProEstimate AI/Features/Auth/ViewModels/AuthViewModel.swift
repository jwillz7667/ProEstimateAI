import Foundation
import Observation

@Observable
final class AuthViewModel {
    // MARK: - Form fields

    var email: String = ""
    var password: String = ""
    var fullName: String = ""
    var companyName: String = ""

    // MARK: - UI state

    var isLoading: Bool = false
    var errorMessage: String?
    var showSignUp: Bool = false
    var showForgotPassword: Bool = false
    var forgotPasswordSuccess: Bool = false

    // MARK: - Dependencies

    private let authService: AuthServiceProtocol
    private let appleSignInCoordinator = AppleSignInCoordinator()
    @MainActor private let googleSignInCoordinator = GoogleSignInCoordinator()

    // MARK: - Init

    init(authService: AuthServiceProtocol = LiveAuthService()) {
        self.authService = authService
    }

    // MARK: - Validation

    var isLoginFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var isSignUpFormValid: Bool {
        // Company name is no longer collected during sign-up — onboarding
        // captures it after the account exists. We auto-fill a placeholder
        // ("<Full Name>'s Company") so the backend signup contract is
        // unchanged.
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 8
    }

    var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Basic email format check
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Actions

    func login(appState: AppState) async {
        guard isLoginFormValid else {
            errorMessage = "Please enter your email and password."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let request = LoginRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            let response = try await authService.login(request: request)
            applyAuthResponse(user: response.user, company: response.company, accessToken: response.accessToken, refreshToken: response.refreshToken, appState: appState)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signUp(appState: AppState) async {
        guard isSignUpFormValid else {
            errorMessage = "Please fill in all fields. Password must be at least 8 characters."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Auto-generate the placeholder company name so the backend
            // contract stays the same; the user names their real company
            // during onboarding after the account is provisioned.
            let trimmedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCompanyName: String = {
                let trimmedCompany = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedCompany.isEmpty { return trimmedCompany }
                return "\(trimmedFullName)'s Company"
            }()
            let request = SignUpRequest(
                fullName: trimmedFullName,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                companyName: resolvedCompanyName,
                password: password
            )
            let response = try await authService.signUp(request: request)
            applyAuthResponse(user: response.user, company: response.company, accessToken: response.accessToken, refreshToken: response.refreshToken, appState: appState)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signInWithApple(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let appleResult = try await appleSignInCoordinator.signIn()
            let request = AppleSignInRequest(
                identityToken: appleResult.identityToken,
                authorizationCode: appleResult.authorizationCode,
                fullName: appleResult.fullName,
                email: appleResult.email
            )
            let response = try await authService.signInWithApple(request: request)
            applyAuthResponse(user: response.user, company: response.company, accessToken: response.accessToken, refreshToken: response.refreshToken, appState: appState)
        } catch let error as AppleSignInError where error == .cancelled {
            // User cancelled — no error message needed
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Native Google sign-in via OAuth 2.0 + PKCE (no Google SDK
    /// required). The coordinator returns a Google-signed ID token; the
    /// backend re-verifies it against Google's JWKS, then logs in or
    /// provisions a fresh account.
    func signInWithGoogle(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await googleSignInCoordinator.signIn()
            let request = GoogleSignInRequest(
                identityToken: result.identityToken,
                fullName: result.fullName,
                email: result.email
            )
            let response = try await authService.signInWithGoogle(request: request)
            applyAuthResponse(
                user: response.user,
                company: response.company,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                appState: appState
            )
        } catch GoogleSignInError.cancelled {
            // User cancelled — no error toast.
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func forgotPassword() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your email address."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let request = ForgotPasswordRequest(email: trimmed)
            _ = try await authService.forgotPassword(request: request)
            forgotPasswordSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func clearError() {
        errorMessage = nil
    }

    func resetForm() {
        email = ""
        password = ""
        fullName = ""
        companyName = ""
        errorMessage = nil
        forgotPasswordSuccess = false
    }

    // MARK: - Private

    private func applyAuthResponse(
        user: User,
        company: Company,
        accessToken: String,
        refreshToken: String,
        appState: AppState
    ) {
        TokenStore.shared.storeTokens(accessToken: accessToken, refreshToken: refreshToken)
        appState.currentUser = AppState.CurrentUser(
            id: user.id,
            email: user.email,
            fullName: user.fullName,
            avatarURL: user.avatarURL
        )
        appState.currentCompany = AppState.CurrentCompany.from(company)
        appState.isAuthenticated = true
    }
}

// MARK: - AppleSignInError Equatable

extension AppleSignInError: Equatable {
    static func == (lhs: AppleSignInError, rhs: AppleSignInError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidCredential, .invalidCredential),
             (.missingIdentityToken, .missingIdentityToken),
             (.missingAuthorizationCode, .missingAuthorizationCode),
             (.cancelled, .cancelled):
            return true
        case (.system, .system):
            return false
        default:
            return false
        }
    }
}
