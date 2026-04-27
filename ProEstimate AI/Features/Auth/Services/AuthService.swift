import Foundation

// MARK: - Protocol

protocol AuthServiceProtocol: Sendable {
    func login(request: LoginRequest) async throws -> LoginResponse
    func signUp(request: SignUpRequest) async throws -> SignUpResponse
    func signInWithApple(request: AppleSignInRequest) async throws -> LoginResponse
    func signInWithGoogle(request: GoogleSignInRequest) async throws -> LoginResponse
    func forgotPassword(request: ForgotPasswordRequest) async throws -> ForgotPasswordResponse
}

// MARK: - Mock Implementation

struct MockAuthService: AuthServiceProtocol {
    func login(request _: LoginRequest) async throws -> LoginResponse {
        // Simulate network delay
        try await Task.sleep(for: .seconds(1))

        return LoginResponse(
            user: User.sample,
            company: Company.sample,
            accessToken: "mock-access-token-\(UUID().uuidString)",
            refreshToken: "mock-refresh-token-\(UUID().uuidString)"
        )
    }

    func signUp(request: SignUpRequest) async throws -> SignUpResponse {
        try await Task.sleep(for: .seconds(1.2))

        let user = User(
            id: "u-\(UUID().uuidString.prefix(8))",
            companyId: "c-\(UUID().uuidString.prefix(8))",
            email: request.email,
            fullName: request.fullName,
            role: .owner,
            avatarURL: nil,
            phone: nil,
            isActive: true,
            createdAt: Date()
        )

        let company = Company(
            id: user.companyId,
            name: request.companyName,
            phone: nil,
            email: request.email,
            address: nil,
            city: nil,
            state: nil,
            zip: nil,
            logoURL: nil,
            primaryColor: "#F97316",
            secondaryColor: "#1E293B",
            defaultTaxRate: 8.25,
            defaultMarkupPercent: 20,
            estimatePrefix: "EST",
            invoicePrefix: "INV",
            proposalPrefix: "PROP",
            nextEstimateNumber: 1001,
            nextInvoiceNumber: 2001,
            nextProposalNumber: 3001,
            defaultLanguage: "en",
            timezone: "America/New_York",
            websiteUrl: nil,
            taxLabel: "Tax",
            createdAt: Date(),
            updatedAt: Date()
        )

        return SignUpResponse(
            user: user,
            company: company,
            accessToken: "mock-access-token-\(UUID().uuidString)",
            refreshToken: "mock-refresh-token-\(UUID().uuidString)"
        )
    }

    func signInWithApple(request _: AppleSignInRequest) async throws -> LoginResponse {
        try await Task.sleep(for: .seconds(0.8))

        return LoginResponse(
            user: User.sample,
            company: Company.sample,
            accessToken: "mock-apple-access-token-\(UUID().uuidString)",
            refreshToken: "mock-apple-refresh-token-\(UUID().uuidString)"
        )
    }

    func signInWithGoogle(request _: GoogleSignInRequest) async throws -> LoginResponse {
        try await Task.sleep(for: .seconds(0.8))

        return LoginResponse(
            user: User.sample,
            company: Company.sample,
            accessToken: "mock-google-access-token-\(UUID().uuidString)",
            refreshToken: "mock-google-refresh-token-\(UUID().uuidString)"
        )
    }

    func forgotPassword(request _: ForgotPasswordRequest) async throws -> ForgotPasswordResponse {
        try await Task.sleep(for: .seconds(0.8))

        return ForgotPasswordResponse(
            message: "If an account with that email exists, a reset link has been sent."
        )
    }
}
