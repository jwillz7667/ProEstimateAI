import Foundation

/// The 8-state subscription entitlement enum.
/// Never collapse these into a single boolean like `isPro`.
/// The backend is the source of truth, but the client mirrors
/// this enum for immediate UI responsiveness.
///
/// State transitions:
/// - FREE -> TRIAL_ACTIVE (starts trial)
/// - TRIAL_ACTIVE -> PRO_ACTIVE (trial converts to paid)
/// - TRIAL_ACTIVE -> EXPIRED (trial canceled, period ends)
/// - PRO_ACTIVE -> GRACE_PERIOD (payment fails, grace starts)
/// - GRACE_PERIOD -> PRO_ACTIVE (payment recovers)
/// - GRACE_PERIOD -> EXPIRED (grace period ends without recovery)
/// - PRO_ACTIVE -> CANCELED_ACTIVE (user cancels, still within paid period)
/// - CANCELED_ACTIVE -> EXPIRED (paid period ends)
/// - Any active state -> REVOKED (Apple refund/revoke)
enum SubscriptionState: String, Codable, CaseIterable, Sendable {
    case free = "FREE"
    case trialActive = "TRIAL_ACTIVE"
    case proActive = "PRO_ACTIVE"
    case gracePeriod = "GRACE_PERIOD"
    case billingRetry = "BILLING_RETRY"
    case canceledActive = "CANCELED_ACTIVE"
    case expired = "EXPIRED"
    case revoked = "REVOKED"
}

// MARK: - Convenience

extension SubscriptionState {
    /// Whether the user currently has full Pro feature access.
    /// This includes trial, active, grace period, billing retry, and canceled-but-active.
    var hasProAccess: Bool {
        switch self {
        case .trialActive, .proActive, .gracePeriod, .billingRetry, .canceledActive:
            return true
        case .free, .expired, .revoked:
            return false
        }
    }

    /// Whether the user is on a free plan (no active subscription).
    var isFree: Bool {
        self == .free
    }

    /// Whether there is a billing issue that should surface a warning banner.
    var hasBillingIssue: Bool {
        self == .gracePeriod || self == .billingRetry
    }

    /// Whether the subscription has ended and premium access is lost.
    var isTerminal: Bool {
        self == .expired || self == .revoked
    }

    /// Human-readable label for display in settings and dashboard.
    var displayLabel: String {
        switch self {
        case .free: return "Free"
        case .trialActive: return "Pro Trial"
        case .proActive: return "Pro Active"
        case .gracePeriod: return "Grace Period"
        case .billingRetry: return "Billing Retry"
        case .canceledActive: return "Canceled (Active)"
        case .expired: return "Expired"
        case .revoked: return "Revoked"
        }
    }
}
