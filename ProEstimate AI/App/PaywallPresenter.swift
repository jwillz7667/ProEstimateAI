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
    var activeLimitNotice: PaywallDecision?

    private var entitlementStore: EntitlementStore?
    private var offeredLoginSession: UUID?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "PaywallPresenter")

    /// `TokenStore.sessionIdentifier` is regenerated on every cold launch,
    /// so the in-memory session check alone re-shows the login offer almost
    /// every time the app opens. Persist when each user last saw (or
    /// declined) it and cap it to once per `loginOfferInterval`.
    private let defaults: UserDefaults
    static let loginOfferInterval: TimeInterval = 24 * 60 * 60
    private static let loginOfferKeyPrefix = "paywall.loginOffer.lastHandled."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Wire the presenter to the live entitlement store.
    /// Called once during app bootstrap, before any paywall trigger fires.
    /// Until configured, `present(_:)` falls through unconditionally so
    /// previews and unit tests still work without booting the full graph.
    func configure(entitlementStore: EntitlementStore) {
        self.entitlementStore = entitlementStore
    }

    /// Present a paywall, unless the current user already has Pro access.
    func present(_ decision: PaywallDecision) {
        if decision.placement.isUsageLimit {
            activeLimitNotice = decision
            return
        }
        if let entitlementStore, entitlementStore.hasProAccess, !entitlementStore.isAccountTrial, !decision.blocking {
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

    /// Once per signed-in session, after authoritative access has loaded.
    /// Dismissing does not consume the trial or bypass premium action checks.
    func presentLoginOffer(sessionID: UUID, userID: String? = nil, now: Date = Date()) {
        guard offeredLoginSession != sessionID, activeDecision == nil,
              let entitlementStore, entitlementStore.snapshot != nil else { return }
        offeredLoginSession = sessionID
        guard !entitlementStore.hasProAccess || entitlementStore.isAccountTrial else { return }
        if let userID {
            if let last = lastLoginOfferDate(for: userID),
               now.timeIntervalSince(last) < Self.loginOfferInterval {
                return
            }
            recordLoginOffer(for: userID, at: now)
        }
        present(.loginOffer(trialEndsAt: entitlementStore.isAccountTrial ? entitlementStore.snapshot?.trialEndsAt : nil))
    }

    /// The user already saw the plans pitch (onboarding offer page) and chose
    /// to continue. Don't follow that with a second sales sheet.
    func markLoginOfferHandled(sessionID: UUID, userID: String?, now: Date = Date()) {
        offeredLoginSession = sessionID
        if let userID { recordLoginOffer(for: userID, at: now) }
    }

    private func lastLoginOfferDate(for userID: String) -> Date? {
        let value = defaults.double(forKey: Self.loginOfferKeyPrefix + userID)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    private func recordLoginOffer(for userID: String, at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.loginOfferKeyPrefix + userID)
    }

    func reset() {
        offeredLoginSession = nil
        activeDecision = nil
        activeLimitNotice = nil
    }
}
