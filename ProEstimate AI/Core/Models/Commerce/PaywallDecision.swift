import Foundation

/// Determines how and why a paywall should be presented to the user.
/// The backend evaluates the user's entitlement and usage state,
/// then returns a `PaywallDecision` with all the copy and configuration
/// needed to render the paywall UI. This keeps paywall logic server-driven
/// and allows A/B testing without app updates.
struct PaywallDecision: Codable, Equatable, Sendable {
    let placement: PaywallPlacement
    let triggerReason: String
    let blocking: Bool
    let headline: String
    let subheadline: String
    let primaryCtaTitle: String
    let secondaryCtaTitle: String?
    let showContinueFree: Bool
    let showRestorePurchases: Bool
    let recommendedProductId: String?
    let availableProducts: [StoreProductModel]?

    enum CodingKeys: String, CodingKey {
        case placement
        case triggerReason = "trigger_reason"
        case blocking
        case headline
        case subheadline
        case primaryCtaTitle = "primary_cta_title"
        case secondaryCtaTitle = "secondary_cta_title"
        case showContinueFree = "show_continue_free"
        case showRestorePurchases = "show_restore_purchases"
        case recommendedProductId = "recommended_product_id"
        case availableProducts = "available_products"
    }
}

// MARK: - Paywall Placement

/// Identifies the context in which a paywall is shown.
/// Each placement maps to a specific user action or screen trigger.
/// Placements are configurable so copy and experiments can evolve independently.
enum PaywallPlacement: String, Codable, CaseIterable, Sendable {
    case onboardingSoftGate = "ONBOARDING_SOFT_GATE"
    case postFirstGeneration = "POST_FIRST_GENERATION"
    case postFirstQuoteExport = "POST_FIRST_QUOTE_EXPORT"
    case generationLimitHit = "GENERATION_LIMIT_HIT"
    case quoteLimitHit = "QUOTE_LIMIT_HIT"
    case invoiceLocked = "INVOICE_LOCKED"
    case brandingLocked = "BRANDING_LOCKED"
    case approvalShareLocked = "APPROVAL_SHARE_LOCKED"
    case watermarkRemovalLocked = "WATERMARK_REMOVAL_LOCKED"
    case settingsUpgrade = "SETTINGS_UPGRADE"
}

// MARK: - Convenience

extension PaywallPlacement {
    /// Whether this placement is a soft gate that allows the user to continue for free.
    var isSoftGate: Bool {
        switch self {
        case .onboardingSoftGate, .postFirstGeneration, .postFirstQuoteExport, .settingsUpgrade:
            return true
        case .generationLimitHit, .quoteLimitHit, .invoiceLocked,
             .brandingLocked, .approvalShareLocked, .watermarkRemovalLocked:
            return false
        }
    }

    /// Whether this placement blocks the user from proceeding without subscribing.
    var isHardGate: Bool {
        !isSoftGate
    }
}

// MARK: - Sample Data

extension PaywallDecision {
    /// Sample soft-gate decision shown after first generation.
    static let sampleSoftGate = PaywallDecision(
        placement: .postFirstGeneration,
        triggerReason: "First AI preview generated",
        blocking: false,
        headline: "Win more jobs in minutes",
        subheadline: "Create AI remodel previews, polished quotes, and branded proposals.",
        primaryCtaTitle: "Start Free Trial",
        secondaryCtaTitle: "Continue with Free Plan",
        showContinueFree: true,
        showRestorePurchases: true,
        recommendedProductId: AppConstants.monthlyProductID,
        availableProducts: [.sampleMonthly, .sampleAnnual]
    )

    /// Sample hard-gate decision shown when generation credits are exhausted.
    static let sampleHardGate = PaywallDecision(
        placement: .generationLimitHit,
        triggerReason: "Free generation credits exhausted",
        blocking: true,
        headline: "You've used all 3 free AI previews",
        subheadline: "Start your free trial to keep generating remodel previews.",
        primaryCtaTitle: "Start Free Trial",
        secondaryCtaTitle: nil,
        showContinueFree: false,
        showRestorePurchases: true,
        recommendedProductId: AppConstants.monthlyProductID,
        availableProducts: [.sampleMonthly, .sampleAnnual]
    )
}
