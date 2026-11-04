import Foundation

enum AppConstants {
    // MARK: - API

    static let apiBaseURL = "https://proestimate-api-production-75e5.up.railway.app/v1"

    // MARK: - StoreKit Product IDs

    static let subscriptionGroupID = "proestimate_pro"
    /// Pro Monthly — includes 20 AI previews and 20 AI estimates per rolling 30 days.
    static let proMonthlyProductID = "proestimate.pro.monthly"
    /// Pro Annual — same caps as Pro Monthly, billed yearly.
    static let proAnnualProductID = "proestimate.pro.annual"

    /// Backwards-compatible aliases. Existing callsites still resolve;
    /// new code should use the tier-explicit identifiers above.
    static let monthlyProductID = proMonthlyProductID
    static let annualProductID = proAnnualProductID

    /// Every period the paywall renders. Order is the on-screen
    /// ordering: Pro Monthly · Pro Annual.
    static let allSubscriptionProductIDs: [String] = [
        proMonthlyProductID,
        proAnnualProductID,
    ]

    // MARK: - Free Tier

    /// AI generation requires an active App Store subscription or trial.
    /// Historical starter credits never unlock a paid generation request.
    static let freeGenerationCredits = 0

    /// Quote / proposal exports remain Pro-gated. Free users hit the
    /// paywall on the first export attempt — no starter pack here.
    static let freeQuoteExportCredits = 0

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
