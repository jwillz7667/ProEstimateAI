import Foundation

/// A point-in-time snapshot of a user's entitlement state from the backend.
/// This is the canonical representation of what a user can do right now —
/// their subscription state, plan, feature flags, and usage credits.
/// The backend is always the source of truth; this struct mirrors the
/// `EntitlementSnapshotDto` from the API.
struct EntitlementSnapshot: Codable, Equatable, Sendable {
    let subscriptionState: SubscriptionState
    let currentPlanCode: PlanCode
    let featureFlags: [String: Bool]
    let usage: [UsageBucket]
    let renewalDate: Date?
    let trialEndsAt: Date?
    let gracePeriodEndsAt: Date?
    let isAutoRenewEnabled: Bool?
    let billingWarning: String?

    enum CodingKeys: String, CodingKey {
        case subscriptionState = "subscription_state"
        case currentPlanCode = "current_plan_code"
        case featureFlags = "feature_flags"
        case usage
        case renewalDate = "renewal_date"
        case trialEndsAt = "trial_ends_at"
        case gracePeriodEndsAt = "grace_period_ends_at"
        case isAutoRenewEnabled = "is_auto_renew_enabled"
        case billingWarning = "billing_warning"
    }
}

// MARK: - Plan Code

/// Identifies which plan a user is on. Matches the backend `PlanCode` enum.
enum PlanCode: String, Codable, CaseIterable, Sendable {
    case freeStarter = "FREE_STARTER"
    case proMonthly = "PRO_MONTHLY"
    case proAnnual = "PRO_ANNUAL"
}

extension PlanCode {
    var displayName: String {
        switch self {
        case .freeStarter: "Free"
        case .proMonthly: "Pro Monthly"
        case .proAnnual: "Pro Annual"
        }
    }
}

// MARK: - Usage Metric Code

/// Identifies the type of metered usage. Matches the backend `UsageMetricCode` enum.
enum UsageMetricCode: String, Codable, CaseIterable, Sendable {
    case aiGeneration = "AI_GENERATION"
    case quoteExport = "QUOTE_EXPORT"
}

// MARK: - Usage Bucket

/// Represents the current state of a metered usage allowance.
/// Each bucket tracks how many of a given action are included vs consumed.
struct UsageBucket: Codable, Equatable, Sendable {
    let metricCode: UsageMetricCode
    let includedQuantity: Int
    let consumedQuantity: Int
    let remainingQuantity: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case metricCode = "metric_code"
        case includedQuantity = "included_quantity"
        case consumedQuantity = "consumed_quantity"
        case remainingQuantity = "remaining_quantity"
        case source
    }
}

// MARK: - Feature Code

/// All feature flags that the backend can enable/disable per entitlement.
/// Used as keys in `EntitlementSnapshot.featureFlags`.
enum FeatureCode: String, CaseIterable, Sendable {
    case canGeneratePreview = "CAN_GENERATE_PREVIEW"
    case canExportQuote = "CAN_EXPORT_QUOTE"
    case canRemoveWatermark = "CAN_REMOVE_WATERMARK"
    case canUseBranding = "CAN_USE_BRANDING"
    case canCreateInvoice = "CAN_CREATE_INVOICE"
    case canShareApprovalLink = "CAN_SHARE_APPROVAL_LINK"
    case canExportMaterialLinks = "CAN_EXPORT_MATERIAL_LINKS"
    case canUseHighResPreview = "CAN_USE_HIGH_RES_PREVIEW"
}

// MARK: - Convenience

extension EntitlementSnapshot {
    /// Check whether a specific feature is enabled.
    func hasFeature(_ feature: FeatureCode) -> Bool {
        featureFlags[feature.rawValue] ?? false
    }

    /// Remaining count for a given usage metric, or nil if not tracked.
    func remaining(for metric: UsageMetricCode) -> Int? {
        usage.first { $0.metricCode == metric }?.remainingQuantity
    }

    /// Number of days until trial ends, or nil if not in trial.
    var trialDaysRemaining: Int? {
        guard let trialEndsAt, subscriptionState == .trialActive else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEndsAt).day
        return max(0, days ?? 0)
    }

    /// Whether the user has any remaining free generation credits.
    var hasGenerationCredits: Bool {
        (remaining(for: .aiGeneration) ?? 0) > 0
    }

    /// Whether the user has any remaining free quote export credits.
    var hasQuoteExportCredits: Bool {
        (remaining(for: .quoteExport) ?? 0) > 0
    }
}

// MARK: - Sample Data

extension EntitlementSnapshot {
    /// Sample free-tier snapshot with starter credits.
    static let sampleFree = EntitlementSnapshot(
        subscriptionState: .free,
        currentPlanCode: .freeStarter,
        featureFlags: [
            FeatureCode.canGeneratePreview.rawValue: true,
            FeatureCode.canExportQuote.rawValue: true,
            FeatureCode.canRemoveWatermark.rawValue: false,
            FeatureCode.canUseBranding.rawValue: false,
            FeatureCode.canCreateInvoice.rawValue: false,
            FeatureCode.canShareApprovalLink.rawValue: false,
            FeatureCode.canExportMaterialLinks.rawValue: false,
            FeatureCode.canUseHighResPreview.rawValue: false,
        ],
        usage: [
            UsageBucket(
                metricCode: .aiGeneration,
                includedQuantity: 3,
                consumedQuantity: 1,
                remainingQuantity: 2,
                source: "free_starter"
            ),
            UsageBucket(
                metricCode: .quoteExport,
                includedQuantity: 3,
                consumedQuantity: 0,
                remainingQuantity: 3,
                source: "free_starter"
            ),
        ],
        renewalDate: nil,
        trialEndsAt: nil,
        gracePeriodEndsAt: nil,
        isAutoRenewEnabled: nil,
        billingWarning: nil
    )

    /// Sample Pro-active snapshot.
    static let samplePro = EntitlementSnapshot(
        subscriptionState: .proActive,
        currentPlanCode: .proMonthly,
        featureFlags: [
            FeatureCode.canGeneratePreview.rawValue: true,
            FeatureCode.canExportQuote.rawValue: true,
            FeatureCode.canRemoveWatermark.rawValue: true,
            FeatureCode.canUseBranding.rawValue: true,
            FeatureCode.canCreateInvoice.rawValue: true,
            FeatureCode.canShareApprovalLink.rawValue: true,
            FeatureCode.canExportMaterialLinks.rawValue: true,
            FeatureCode.canUseHighResPreview.rawValue: true,
        ],
        usage: [],
        renewalDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
        trialEndsAt: nil,
        gracePeriodEndsAt: nil,
        isAutoRenewEnabled: true,
        billingWarning: nil
    )
}
