import Foundation
import Observation
import os.log

/// The single source of truth for the current user's subscription entitlement.
/// All feature-gating, paywall, and subscription UI reads from this store.
/// Updates come from backend API calls (on launch, after purchase, on foreground).
///
/// This is an `@Observable` singleton — inject it into the SwiftUI environment
/// via `.environment()` and read properties directly in views.
@Observable
final class EntitlementStore {
    // MARK: - Shared Instance

    static let shared = EntitlementStore()

    // MARK: - Published State

    /// The current entitlement snapshot from the backend.
    /// `nil` until the first successful fetch.
    private(set) var snapshot: EntitlementSnapshot?

    /// Whether entitlements are currently being loaded.
    private(set) var isLoading: Bool = false

    /// The last error encountered during a refresh, if any.
    private(set) var lastError: Error?

    // MARK: - Dependencies

    private var commerceAPI: CommerceAPIClientProtocol?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "EntitlementStore")

    // MARK: - Init

    private init() {}

    /// Configure the store with its API dependency.
    /// Call once during app initialization before any entitlement checks.
    func configure(commerceAPI: CommerceAPIClientProtocol) {
        self.commerceAPI = commerceAPI
    }

    // MARK: - Computed Properties

    /// Whether the user currently has Pro-level access (trial, active, grace, billing retry, or canceled-active).
    var hasProAccess: Bool {
        snapshot?.subscriptionState.hasProAccess ?? false
    }

    /// Whether the user is a paying Pro subscriber (not trial).
    var isPremium: Bool {
        snapshot?.subscriptionState == .proActive
    }

    /// Whether the user is in an active free trial.
    var isTrial: Bool {
        snapshot?.subscriptionState == .trialActive
    }

    /// Whether the user is in a billing grace period.
    var isInGracePeriod: Bool {
        snapshot?.subscriptionState == .gracePeriod
    }

    /// Whether the user is on the free starter plan.
    var isFree: Bool {
        snapshot?.subscriptionState.isFree ?? true
    }

    /// Whether there is a billing issue (grace period or retry).
    var hasBillingIssue: Bool {
        snapshot?.subscriptionState.hasBillingIssue ?? false
    }

    /// The current subscription state, defaulting to `.free` if unknown.
    var subscriptionState: SubscriptionState {
        snapshot?.subscriptionState ?? .free
    }

    /// The current plan code, defaulting to `.freeStarter` if unknown.
    var currentPlanCode: PlanCode {
        snapshot?.currentPlanCode ?? .freeStarter
    }

    /// Number of days remaining in trial, or nil if not in trial.
    var trialDaysRemaining: Int? {
        snapshot?.trialDaysRemaining
    }

    /// The renewal date for the current subscription, or nil.
    var renewalDate: Date? {
        snapshot?.renewalDate
    }

    /// Whether auto-renew is enabled.
    var isAutoRenewEnabled: Bool {
        snapshot?.isAutoRenewEnabled ?? false
    }

    /// Any billing warning message from the backend.
    var billingWarning: String? {
        snapshot?.billingWarning
    }

    // MARK: - Feature Checks

    /// Check whether a specific feature flag is enabled.
    func hasFeature(_ feature: FeatureCode) -> Bool {
        snapshot?.hasFeature(feature) ?? false
    }

    // MARK: - Actions

    /// Fetch the latest entitlement snapshot from the backend.
    /// Call on app launch, return to foreground, and after purchases.
    func refresh() async {
        guard let commerceAPI else {
            logger.warning("EntitlementStore.refresh() called before configure(). Skipping.")
            return
        }

        isLoading = true
        lastError = nil

        do {
            let updatedSnapshot = try await commerceAPI.fetchEntitlement()
            snapshot = updatedSnapshot
            logger.info("Entitlement refreshed. State: \(updatedSnapshot.subscriptionState.rawValue), Plan: \(updatedSnapshot.currentPlanCode.rawValue)")
        } catch {
            lastError = error
            logger.error("Failed to refresh entitlement: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Update the local snapshot directly (e.g., after a purchase sync returns a new snapshot).
    func updateFromSnapshot(_ newSnapshot: EntitlementSnapshot) async {
        snapshot = newSnapshot
        logger.info("Entitlement updated from snapshot. State: \(newSnapshot.subscriptionState.rawValue)")
    }

    /// Reset the store (e.g., on sign-out).
    func reset() {
        snapshot = nil
        lastError = nil
        isLoading = false
        logger.info("EntitlementStore reset.")
    }
}

// MARK: - Preview Support

extension EntitlementStore {
    /// Create a store pre-loaded with a snapshot for SwiftUI previews.
    static func preview(snapshot: EntitlementSnapshot = .sampleFree) -> EntitlementStore {
        let store = EntitlementStore()
        store.snapshot = snapshot
        return store
    }
}
