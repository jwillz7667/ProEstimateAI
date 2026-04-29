import SwiftUI

/// At-a-glance subscription status capsule for the navigation bar.
///
/// Renders nothing for free users (so the badge silently disappears the
/// instant a user subscribes and the entitlement snapshot updates). For
/// active subscribers it renders a tier-aware capsule: a flat orange
/// "PRO" / trial badge, or a gradient orange→fuchsia "PREMIUM" badge for
/// the Premium tier. Tapping the badge switches to the Settings tab so
/// the user can manage their subscription.
///
/// The badge reads directly from `EntitlementStore` via `@Environment`,
/// so it re-renders automatically as soon as a purchase, restore, or
/// background `Transaction.updates` event mutates the snapshot.
struct SubscriptionBadge: View {
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(AppState.self) private var appState

    var body: some View {
        if entitlementStore.hasProAccess, let style = badgeStyle {
            Button(action: openSubscriptionSettings) {
                badgeContent(style: style)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(style.accessibilityLabel)
            .accessibilityHint("Opens subscription settings")
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Badge Content

    private func badgeContent(style: BadgeStyle) -> some View {
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .font(.system(size: 10, weight: .bold))

            Text(style.label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(style.background, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: style.shadowColor.opacity(0.45), radius: 6, x: 0, y: 2)
    }

    // MARK: - Actions

    private func openSubscriptionSettings() {
        appState.selectedTab = .settings
    }

    // MARK: - Style Resolution

    /// The badge style for the current entitlement, or `nil` if the user
    /// is not a subscriber (in which case the body returns no view at all).
    private var badgeStyle: BadgeStyle? {
        let state = entitlementStore.subscriptionState
        let tier = entitlementStore.currentPlanCode.tier

        switch state {
        case .gracePeriod, .billingRetry:
            return .billingIssue
        case .trialActive:
            return .trial(daysRemaining: entitlementStore.trialDaysRemaining)
        case .proActive, .canceledActive, .adminOverride:
            return tier == .premium ? .premium : .pro
        case .free, .expired, .revoked:
            return nil
        }
    }
}

// MARK: - Badge Style

private enum BadgeStyle {
    case pro
    case premium
    case trial(daysRemaining: Int?)
    case billingIssue

    var label: String {
        switch self {
        case .pro: return "PRO"
        case .premium: return "PREMIUM"
        case let .trial(daysRemaining):
            if let days = daysRemaining, days > 0 {
                return "TRIAL · \(days)D"
            }
            return "TRIAL"
        case .billingIssue: return "BILLING"
        }
    }

    var icon: String {
        switch self {
        case .pro: return "checkmark.seal.fill"
        case .premium: return "crown.fill"
        case .trial: return "sparkles"
        case .billingIssue: return "exclamationmark.triangle.fill"
        }
    }

    var background: AnyShapeStyle {
        switch self {
        case .pro:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        ColorTokens.primaryOrange,
                        Color(hex: 0xEA580C),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .premium:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: 0xFB923C),
                        Color(hex: 0xC026D3),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .trial:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        ColorTokens.primaryOrange.opacity(0.95),
                        Color(hex: 0xF59E0B),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .billingIssue:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: 0xF59E0B),
                        Color(hex: 0xEF4444),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    var shadowColor: Color {
        switch self {
        case .pro: return ColorTokens.primaryOrange
        case .premium: return Color(hex: 0xC026D3)
        case .trial: return ColorTokens.primaryOrange
        case .billingIssue: return Color(hex: 0xEF4444)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .pro: return "Pro subscription active"
        case .premium: return "Premium subscription active"
        case let .trial(daysRemaining):
            if let days = daysRemaining {
                return "Free trial active, \(days) day\(days == 1 ? "" : "s") remaining"
            }
            return "Free trial active"
        case .billingIssue: return "Subscription billing issue"
        }
    }
}

// MARK: - Preview

#Preview("Free (hidden)") {
    NavigationStack {
        Color.gray.opacity(0.1)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SubscriptionBadge()
                }
            }
    }
    .environment(EntitlementStore.preview(snapshot: .sampleFree))
    .environment(AppState())
}

#Preview("Pro") {
    NavigationStack {
        Color.gray.opacity(0.1)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SubscriptionBadge()
                }
            }
    }
    .environment(EntitlementStore.preview(snapshot: .samplePro))
    .environment(AppState())
}

#Preview("Grace") {
    NavigationStack {
        Color.gray.opacity(0.1)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SubscriptionBadge()
                }
            }
    }
    .environment(EntitlementStore.preview(snapshot: .sampleGracePeriod))
    .environment(AppState())
}
