import Foundation

/// Production implementation of `AuthServiceProtocol` that delegates
/// all authentication calls to the backend REST API via `APIClient`.
final class LiveAuthService: AuthServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - AuthServiceProtocol

    func login(request: LoginRequest) async throws -> LoginResponse {
        try await apiClient.request(
            .authLogin(email: request.email, password: request.password)
        )
    }

    func signUp(request: SignUpRequest) async throws -> SignUpResponse {
        try await apiClient.request(
            .authSignup(
                email: request.email,
                password: request.password,
                fullName: request.fullName,
                companyName: request.companyName
            )
        )
    }

    func signInWithApple(request: AppleSignInRequest) async throws -> LoginResponse {
        try await apiClient.request(.authAppleSignIn(body: request))
    }

    func signInWithGoogle(request: GoogleSignInRequest) async throws -> LoginResponse {
        try await apiClient.request(.authGoogleSignIn(body: request))
    }

    func forgotPassword(request: ForgotPasswordRequest) async throws -> ForgotPasswordResponse {
        try await apiClient.request(.authForgotPassword(email: request.email))
    }
}
