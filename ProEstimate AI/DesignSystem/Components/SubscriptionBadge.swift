import SwiftUI

/// At-a-glance subscription status capsule for the navigation bar.
///
/// Renders nothing for free users (so the badge silently disappears the
/// instant a user subscribes and the entitlement snapshot updates). For
/// active subscribers it renders a tier-aware capsule: a flat orange
/// "PRO" / trial badge, or a gold "PREMIUM" badge with a crown for the
/// Premium tier. Tapping the badge opens a non-blocking subscription
/// status sheet that shows the active tier, included features, and (for
/// Pro) an unobtrusive Premium upsell. Billing-issue states still route
/// straight to Settings so the user can fix payment quickly.
///
/// The badge reads directly from `EntitlementStore` via `@Environment`,
/// so it re-renders automatically as soon as a purchase, restore, or
/// background `Transaction.updates` event mutates the snapshot.
struct SubscriptionBadge: View {
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(AppState.self) private var appState
    @State private var showStatus = false

    var body: some View {
        if entitlementStore.hasProAccess, let style = badgeStyle {
            Button(action: handleTap) {
                badgeContent(style: style)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(style.accessibilityLabel)
            .accessibilityHint(style.accessibilityHint)
            .transition(.scale.combined(with: .opacity))
            .sheet(isPresented: $showStatus) {
                SubscriptionStatusView()
            }
        }
    }

    // MARK: - Badge Content

    /// Per-tier content. Pro is a flat "PRO" text capsule (no icon —
    /// the word IS the brand); Premium collapses to a single crown
    /// glyph (the symbol carries the meaning, no need to also write
    /// "PREMIUM"); trial and billing-issue keep the icon + label combo
    /// because their text carries time-sensitive context (days
    /// remaining, "Action needed") that an icon alone can't convey.
    @ViewBuilder
    private func badgeContent(style: BadgeStyle) -> some View {
        switch style {
        case .pro:
            Text("PRO")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(style.background, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: style.shadowColor.opacity(0.45), radius: 6, x: 0, y: 2)
        case .premium:
            Image(systemName: "crown.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 22)
                .background(style.background, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: style.shadowColor.opacity(0.45), radius: 6, x: 0, y: 2)
        case .trial, .billingIssue:
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
    }

    // MARK: - Actions

    private func handleTap() {
        // Billing problems are time-sensitive — short-circuit straight to
        // Settings so the user can fix payment without an extra modal hop.
        if entitlementStore.hasBillingIssue {
            appState.selectedTab = .settings
        } else {
            showStatus = true
        }
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
            // Gold gradient (amber-300 → amber-600) signals "top tier"
            // without competing with the orange brand accent.
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: 0xFCD34D),
                        Color(hex: 0xD97706),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
        case .premium: return Color(hex: 0xD97706)
        case .trial: return ColorTokens.primaryOrange
        case .billingIssue: return Color(hex: 0xEF4444)
        }
    }

    var accessibilityHint: String {
        switch self {
        case .pro, .trial: return "Opens your subscription status with an option to upgrade to Premium"
        case .premium: return "Opens your Premium subscription status"
        case .billingIssue: return "Opens settings so you can fix your billing"
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
