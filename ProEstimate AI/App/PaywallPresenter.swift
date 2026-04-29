import Foundation
import Observation
import os.log

/// Centralized paywall presentation coordinator.
///
/// Any view or viewmodel triggers a paywall by calling `present(_:)`. The
/// app root observes `activeDecision` and presents `PaywallHostView` as a
/// sheet.
///
/// Once configured with the live `EntitlementStore`, `present(_:)` is a
/// no-op for users with active Pro access. This is the global safety net:
/// if a stale or misplaced call site fires after the user subscribes, the
/// paywall is silently suppressed instead of harassing a paying customer.
/// Individual feature gates still short-circuit at the call site, but this
/// presenter-level guard catches everything that slips past them (e.g. the
/// post-action soft upsell that historically fired on every successful
/// generation regardless of tier).
@Observable
final class PaywallPresenter {
    /// The decision currently driving the paywall sheet, or `nil` when no
    /// paywall is shown.
    var activeDecision: PaywallDecision?

    private var entitlementStore: EntitlementStore?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "PaywallPresenter")

    /// Wire the presenter to the live entitlement store.
    /// Called once during app bootstrap, before any paywall trigger fires.
    /// Until configured, `present(_:)` falls through unconditionally so
    /// previews and unit tests still work without booting the full graph.
    func configure(entitlementStore: EntitlementStore) {
        self.entitlementStore = entitlementStore
    }

    /// Present a paywall, unless the current user already has Pro access.
    func present(_ decision: PaywallDecision) {
        if let entitlementStore, entitlementStore.hasProAccess {
            let placement = decision.placement.rawValue
            let state = entitlementStore.subscriptionState.rawValue
            logger.info("Paywall suppressed for active subscriber. placement=\(placement) state=\(state)")
            return
        }
        activeDecision = decision
    }

    func dismiss() {
        activeDecision = nil
    }
}
