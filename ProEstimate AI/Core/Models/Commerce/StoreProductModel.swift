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
