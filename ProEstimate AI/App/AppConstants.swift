import Foundation

enum AppConstants {
    // MARK: - API
    static let apiBaseURL = "https://proestimate-api-production.up.railway.app/v1"

    // MARK: - StoreKit Product IDs
    static let subscriptionGroupID = "proestimate_pro"
    static let monthlyProductID = "proestimate.pro.monthly"
    static let annualProductID = "proestimate.pro.annual"

    // MARK: - Free Tier Limits
    static let freeGenerationCredits = 3
    static let freeQuoteExportCredits = 3

    // MARK: - Web & Legal URLs
    /// Canonical marketing site domain (matches the Next.js web app on Vercel).
    static let marketingSiteURL = URL(string: "https://proestimateai.com")!
    static let termsOfServiceURL = URL(string: "https://proestimateai.com/terms")!
    static let privacyPolicyURL = URL(string: "https://proestimateai.com/privacy")!
    static let supportEmailURL = URL(string: "mailto:support@proestimateai.com")!
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    /// Root used to build client-facing proposal share URLs (`/proposal/{token}`).
    static let proposalShareBaseURL = URL(string: "https://proestimateai.com/proposal")!

    // MARK: - Build Flags
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var useMockData: Bool {
        return false
    }

    // MARK: - Keychain
    static let keychainServiceName = "ai.proestimate.ios"
    static let keychainAccessTokenKey = "access_token"
    static let keychainRefreshTokenKey = "refresh_token"

    // MARK: - Bundle
    static let bundleID = "Res.ProEstimate-AI"
}
