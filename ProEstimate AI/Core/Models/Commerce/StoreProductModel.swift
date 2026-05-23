import Foundation

/// App-facing representation of a StoreKit subscription product.
/// This model normalizes data from both the backend product catalog and
/// StoreKit's `Product` type into a single display-ready struct.
/// Product IDs and plan codes are centralized in `AppConstants`.
struct StoreProductModel: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier — uses `productId` for Identifiable conformance.
    var id: String {
        productId
    }

    let productId: String
    let planCode: PlanCode
    let displayName: String
    let description: String
    let priceDisplay: String
    let billingPeriodLabel: String
    let hasIntroOffer: Bool
    let introOfferDisplayText: String?
    let isEligibleForIntroOffer: Bool?
    let isFeatured: Bool
    let savingsText: String?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case planCode = "plan_code"
        case displayName = "display_name"
        case description
        case priceDisplay = "price_display"
        case billingPeriodLabel = "billing_period_label"
        case hasIntroOffer = "has_intro_offer"
        case introOfferDisplayText = "intro_offer_display_text"
        case isEligibleForIntroOffer = "is_eligible_for_intro_offer"
        case isFeatured = "is_featured"
        case savingsText = "savings_text"
    }
}

// MARK: - Convenience

extension StoreProductModel {
    /// Whether this product offers a free trial to the current user.
    var showsTrialBadge: Bool {
        hasIntroOffer && (isEligibleForIntroOffer ?? false)
    }

    /// Tier (Pro vs Premium). Derived from the plan code so the UI
    /// stays in sync with the backend's authoritative classification.
    var tier: PlanTier {
        planCode.tier
    }

    /// True for any monthly subscription (Pro Monthly OR Premium Monthly).
    var isMonthly: Bool {
        planCode.period == .monthly
    }

    /// True for any annual subscription (Pro Annual OR Premium Annual).
    var isAnnual: Bool {
        planCode.period == .annual
    }

    /// True specifically for the two Pro tier products.
    var isPro: Bool {
        tier == .pro
    }

    /// True specifically for the two Premium tier products.
    var isPremium: Bool {
        tier == .premium
    }
}

// MARK: - Canonical fallbacks

extension StoreProductModel {
    /// Tier- and period-correct display fallback used when the live
    /// catalog hasn't returned a matching SKU yet — e.g. Premium hasn't
    /// shipped in App Store Connect, StoreKit is still resolving, or
    /// the backend catalog request failed and the device is offline.
    ///
    /// Without this, the paywall would silently fall through to the
    /// previously-selected (different tier) product so the price and
    /// description on screen would lie about which tier the toggle has
    /// highlighted. This helper guarantees the rendered card always
    /// matches the user's stated intent.
    ///
    /// The pricing strings here MUST mirror what's in App Store Connect.
    /// The purchase flow gates separately on the real StoreKit product
    /// being available, so a fallback never short-circuits a checkout
    /// against a price the user can't actually transact at.
    static func canonicalFallback(tier: PlanTier, isAnnual: Bool) -> StoreProductModel {
        switch (tier, isAnnual) {
        case (.pro, false):
            return StoreProductModel(
                productId: AppConstants.proMonthlyProductID,
                planCode: .proMonthly,
                displayName: "Pro Monthly",
                description: "Solo contractor essentials. 2 projects, 20 AI previews, and 20 estimates per month.",
                priceDisplay: "$29.99/mo",
                billingPeriodLabel: "per month",
                hasIntroOffer: true,
                introOfferDisplayText: "7-day free trial",
                isEligibleForIntroOffer: nil,
                isFeatured: false,
                savingsText: nil
            )
        case (.pro, true):
            return StoreProductModel(
                productId: AppConstants.proAnnualProductID,
                planCode: .proAnnual,
                displayName: "Pro Annual",
                description: "Solo contractor essentials, billed yearly. Same caps as Pro Monthly.",
                priceDisplay: "$249.99/yr",
                billingPeriodLabel: "per year",
                hasIntroOffer: false,
                introOfferDisplayText: nil,
                isEligibleForIntroOffer: nil,
                isFeatured: false,
                savingsText: "Save 17%"
            )
        case (.premium, false):
            return StoreProductModel(
                productId: AppConstants.premiumMonthlyProductID,
                planCode: .premiumMonthly,
                displayName: "Premium Monthly",
                description: "Unlimited projects, AI previews, and estimates — plus priority generation.",
                priceDisplay: "$49.99/mo",
                billingPeriodLabel: "per month",
                hasIntroOffer: false,
                introOfferDisplayText: nil,
                isEligibleForIntroOffer: nil,
                isFeatured: true,
                savingsText: nil
            )
        case (.premium, true):
            return StoreProductModel(
                productId: AppConstants.premiumAnnualProductID,
                planCode: .premiumAnnual,
                displayName: "Premium Annual",
                description: "Unlimited Premium, billed yearly — best value for growing crews.",
                priceDisplay: "$499.99/yr",
                billingPeriodLabel: "per year",
                hasIntroOffer: false,
                introOfferDisplayText: nil,
                isEligibleForIntroOffer: nil,
                isFeatured: false,
                savingsText: "Save 17%"
            )
        case (.free, _):
            // Defensive: the paywall never surfaces Free as a paid tier,
            // but a future caller mis-using the helper shouldn't render
            // an empty card. Fall through to the headline Premium SKU.
            return canonicalFallback(tier: .premium, isAnnual: isAnnual)
        }
    }
}

// MARK: - Sample Data

extension StoreProductModel {
    static let sampleMonthly = StoreProductModel(
        productId: AppConstants.monthlyProductID,
        planCode: .proMonthly,
        displayName: "Pro Monthly",
        description: "Full access, billed monthly",
        priceDisplay: "$29.99/mo",
        billingPeriodLabel: "per month",
        hasIntroOffer: true,
        introOfferDisplayText: "7-day free trial",
        isEligibleForIntroOffer: true,
        isFeatured: false,
        savingsText: nil
    )

    static let sampleAnnual = StoreProductModel(
        productId: AppConstants.proAnnualProductID,
        planCode: .proAnnual,
        displayName: "Pro Annual",
        description: "Full access, billed annually",
        priceDisplay: "$249.99/yr",
        billingPeriodLabel: "per year",
        hasIntroOffer: false,
        introOfferDisplayText: nil,
        isEligibleForIntroOffer: nil,
        isFeatured: false,
        savingsText: "Save 30%"
    )

    static let samplePremiumMonthly = StoreProductModel(
        productId: AppConstants.premiumMonthlyProductID,
        planCode: .premiumMonthly,
        displayName: "Premium Monthly",
        description: "Unlimited projects, image gens, and estimates",
        priceDisplay: "$49.99/mo",
        billingPeriodLabel: "per month",
        hasIntroOffer: false,
        introOfferDisplayText: nil,
        isEligibleForIntroOffer: nil,
        isFeatured: true,
        savingsText: nil
    )

    static let samplePremiumAnnual = StoreProductModel(
        productId: AppConstants.premiumAnnualProductID,
        planCode: .premiumAnnual,
        displayName: "Premium Annual",
        description: "Everything in Premium — save 17% over monthly",
        priceDisplay: "$499.99/yr",
        billingPeriodLabel: "per year",
        hasIntroOffer: false,
        introOfferDisplayText: nil,
        isEligibleForIntroOffer: nil,
        isFeatured: false,
        savingsText: "Save 17%"
    )

    /// Convenience array for previews / mocks.
    static let sampleAll: [StoreProductModel] = [
        .sampleMonthly,
        .sampleAnnual,
        .samplePremiumMonthly,
        .samplePremiumAnnual,
    ]
}
