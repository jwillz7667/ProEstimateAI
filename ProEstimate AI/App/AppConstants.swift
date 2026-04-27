import Foundation

enum AppConstants {
    // MARK: - API

    static let apiBaseURL = "https://proestimate-api-production.up.railway.app/v1"

    // MARK: - StoreKit Product IDs

    static let subscriptionGroupID = "proestimate_pro"
    /// Pro Monthly — capped at 2 projects / 20 image gens / 20 estimates per month.
    static let proMonthlyProductID = "proestimate.pro.monthly"
    /// Pro Annual — same caps as Pro Monthly, billed yearly.
    static let proAnnualProductID = "proestimate.pro.annual"
    /// Premium Monthly — unlimited within fair-use caps. $49.99/mo.
    static let premiumMonthlyProductID = "proestimate.premium.monthly"
    /// Premium Annual — unlimited, billed yearly. $499.99/yr.
    static let premiumAnnualProductID = "proestimate.premium.annual"

    /// Backwards-compatible aliases. Existing callsites still resolve;
    /// new code should use the tier-explicit identifiers above.
    static let monthlyProductID = proMonthlyProductID
    static let annualProductID = proAnnualProductID

    /// Every tier+period the paywall renders. Order is the on-screen
    /// ordering: Pro Monthly · Pro Annual · Premium Monthly · Premium Annual.
    static let allSubscriptionProductIDs: [String] = [
        proMonthlyProductID,
        proAnnualProductID,
        premiumMonthlyProductID,
        premiumAnnualProductID,
    ]

    // MARK: - Free Tier

    /// Free users get zero pre-paid actions. Every paid feature flips to
    /// the paywall on first tap. The previous "3 free AI previews"
    /// concept is retired — these constants stay only so any leftover
    /// references compile until they're refactored away.
    static let freeGenerationCredits = 0
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
