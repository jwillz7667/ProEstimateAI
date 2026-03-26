import Foundation

/// The result of checking whether a user can access a gated feature.
/// Used by `FeatureGateCoordinator` to determine whether to allow an action
/// or present a paywall with the appropriate messaging.
enum FeatureGateResult: Sendable {
    /// The user has access to the feature — proceed.
    case allowed

    /// The user does not have access — present the paywall with this decision.
    case blocked(PaywallDecision)
}

// MARK: - Convenience

extension FeatureGateResult {
    /// Whether the feature is allowed.
    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    /// The paywall decision if the feature is blocked, or `nil` if allowed.
    var paywallDecision: PaywallDecision? {
        if case .blocked(let decision) = self { return decision }
        return nil
    }
}
