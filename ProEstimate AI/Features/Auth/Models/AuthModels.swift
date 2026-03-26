import Foundation

// MARK: - Login

struct LoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct LoginResponse: Codable, Sendable {
    let user: User
    let company: Company
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case user
        case company
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Sign Up

struct SignUpRequest: Codable, Sendable {
    let fullName: String
    let email: String
    let companyName: String
    let password: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case email
        case companyName = "company_name"
        case password
    }
}

struct SignUpResponse: Codable, Sendable {
    let user: User
    let company: Company
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case user
        case company
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Forgot Password

struct ForgotPasswordRequest: Codable, Sendable {
    let email: String
}

struct ForgotPasswordResponse: Codable, Sendable {
    let message: String
}

// MARK: - Apple Sign In

struct AppleSignInRequest: Codable, Sendable {
    let identityToken: String
    let authorizationCode: String
    let fullName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case fullName = "full_name"
        case email
    }
}
