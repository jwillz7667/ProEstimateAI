import Foundation
import Observation

/// ViewModel for the dashboard subscription status card.
/// Reads from `EntitlementStore` and `UsageMeterStore` to present
/// one of four visual variants:
///
/// 1. **Free** — Shows remaining credits meter with upgrade CTA.
/// 2. **Trial** — Shows trial days remaining with countdown.
/// 3. **Pro** — Shows active badge with renewal info.
/// 4. **Grace Period** — Shows billing warning with action required.
@Observable
final class DashboardSubscriptionCardViewModel {
    // MARK: - Dependencies

    private let entitlementStore: EntitlementStore
    private let usageMeterStore: UsageMeterStore

    // MARK: - Init

    init(
        entitlementStore: EntitlementStore = .shared,
        usageMeterStore: UsageMeterStore = .shared
    ) {
        self.entitlementStore = entitlementStore
        self.usageMeterStore = usageMeterStore
    }

    // MARK: - Card Variant

    /// The visual variant to display based on the current subscription state.
    enum CardVariant {
        case free
        case trial
        case pro
        case gracePeriod
    }

    /// The current card variant.
    var variant: CardVariant {
        switch entitlementStore.subscriptionState {
        case .free, .expired, .revoked:
            return .free
        case .trialActive:
            return .trial
        case .proActive, .canceledActive:
            return .pro
        case .gracePeriod, .billingRetry:
            return .gracePeriod
        }
    }

    // MARK: - Free Variant Properties

    /// Remaining AI generation credits.
    var generationsRemaining: Int {
        usageMeterStore.generationsRemaining
    }

    /// Total AI generation credits.
    var generationsTotal: Int {
        usageMeterStore.generationsTotal
    }

    /// Remaining quote export credits.
    var quotesRemaining: Int {
        usageMeterStore.quotesRemaining
    }

    /// Total quote export credits.
    var quotesTotal: Int {
        usageMeterStore.quotesTotal
    }

    // MARK: - Trial Variant Properties

    /// Number of days remaining in the free trial.
    var trialDaysRemaining: Int {
        entitlementStore.trialDaysRemaining ?? 0
    }

    /// Formatted trial expiry message.
    var trialExpiryMessage: String {
        let days = trialDaysRemaining
        if days == 0 {
            return "Trial ends today"
        } else if days == 1 {
            return "1 day remaining in trial"
        } else {
            return "\(days) days remaining in trial"
        }
    }

    // MARK: - Pro Variant Properties

    /// Whether the user is on the canceled-but-active state.
    var isCanceledActive: Bool {
        entitlementStore.subscriptionState == .canceledActive
    }

    /// Human-readable plan label.
    var planLabel: String {
        switch entitlementStore.currentPlanCode {
        case .proMonthly: return "Pro Monthly"
        case .proAnnual: return "Pro Annual"
        case .freeStarter: return "Free"
        }
    }

    /// Formatted renewal date.
    var renewalDateFormatted: String? {
        guard let date = entitlementStore.renewalDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Whether auto-renew is enabled.
    var isAutoRenewEnabled: Bool {
        entitlementStore.isAutoRenewEnabled
    }

    // MARK: - Grace Period Variant Properties

    /// Billing warning message from the backend.
    var billingWarning: String {
        entitlementStore.billingWarning ?? "There's an issue with your payment method."
    }

    /// Formatted grace period end date.
    var gracePeriodEndFormatted: String? {
        guard let date = entitlementStore.snapshot?.gracePeriodEndsAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - General

    /// Whether the subscription state is loaded.
    var isLoaded: Bool {
        entitlementStore.snapshot != nil
    }

    /// The subscription state display label.
    var stateLabel: String {
        entitlementStore.subscriptionState.displayLabel
    }
}

// MARK: - Preview Support

extension DashboardSubscriptionCardViewModel {
    /// Create a view model for free-tier previews.
    static func previewFree() -> DashboardSubscriptionCardViewModel {
        DashboardSubscriptionCardViewModel(
            entitlementStore: .preview(snapshot: .sampleFree),
            usageMeterStore: .preview(generationsRemaining: 2, generationsTotal: 3, quotesRemaining: 3, quotesTotal: 3)
        )
    }

    /// Create a view model for Pro previews.
    static func previewPro() -> DashboardSubscriptionCardViewModel {
        DashboardSubscriptionCardViewModel(
            entitlementStore: .preview(snapshot: .samplePro),
            usageMeterStore: .preview()
        )
    }

    /// Create a view model for trial previews.
    static func previewTrial() -> DashboardSubscriptionCardViewModel {
        let trialSnapshot = EntitlementSnapshot(
            subscriptionState: .trialActive,
            currentPlanCode: .proMonthly,
            featureFlags: EntitlementSnapshot.samplePro.featureFlags,
            usage: [],
            renewalDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
            trialEndsAt: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
            gracePeriodEndsAt: nil,
            isAutoRenewEnabled: true,
            billingWarning: nil
        )
        return DashboardSubscriptionCardViewModel(
            entitlementStore: .preview(snapshot: trialSnapshot),
            usageMeterStore: .preview()
        )
    }
}
