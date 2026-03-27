import Foundation

enum AppConstants {
    // MARK: - API
    static let apiBaseURL = "https://proestimate-api-production.up.railway.app/v1"

    // MARK: - StoreKit Product IDs
    static let subscriptionGroupID = "proestimate_pro"
    static let monthlyProductID = "proestimate.pro.monthly"
    static let annualProductID = "proestimate.pro.annual"

    // MARK: - Free Tier Limits
    static let freeGenerationCredits = 5
    static let freeQuoteExportCredits = 5

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
