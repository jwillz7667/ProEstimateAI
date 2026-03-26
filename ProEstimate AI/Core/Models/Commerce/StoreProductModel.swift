import Foundation

/// App-facing representation of a StoreKit subscription product.
/// This model normalizes data from both the backend product catalog and
/// StoreKit's `Product` type into a single display-ready struct.
/// Product IDs and plan codes are centralized in `AppConstants`.
struct StoreProductModel: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier — uses `productId` for Identifiable conformance.
    var id: String { productId }

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

    /// Whether this is the monthly plan.
    var isMonthly: Bool {
        planCode == .proMonthly
    }

    /// Whether this is the annual plan.
    var isAnnual: Bool {
        planCode == .proAnnual
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
        productId: AppConstants.annualProductID,
        planCode: .proAnnual,
        displayName: "Pro Annual",
        description: "Full access, billed annually",
        priceDisplay: "$249.99/yr",
        billingPeriodLabel: "per year",
        hasIntroOffer: false,
        introOfferDisplayText: nil,
        isEligibleForIntroOffer: nil,
        isFeatured: true,
        savingsText: "Save 30%"
    )
}
