import SwiftUI

/// Dashboard card showing the user's current subscription posture.
///
/// For free / expired / revoked users it surfaces the trial-offer CTA.
/// For active subscribers it switches to a status block showing tier
/// (Pro vs Premium), renewal / trial countdown, and grace-period warnings —
/// no upgrade prompts. The card auto-reads from `EntitlementStore` so it
/// re-renders the moment a purchase or restore mutates the snapshot.
struct DashboardSubscriptionCard: View {
    @Environment(EntitlementStore.self) private var entitlementStore

    var onUpgrade: (() -> Void)?

    var body: some View {
        GlassCard {
            switch entitlementStore.subscriptionState {
            case .free, .expired, .revoked:
                upgradePromptContent
            case .trialActive:
                statusContent(variant: .trial)
            case .proActive, .canceledActive, .adminOverride:
                statusContent(variant: .active)
            case .gracePeriod, .billingRetry:
                statusContent(variant: .billingIssue)
            }
        }
    }

    // MARK: - Active / Trial / Billing-Issue Status

    private enum StatusVariant {
        case active
        case trial
        case billingIssue
    }

    private func statusContent(variant: StatusVariant) -> some View {
        HStack(alignment: .top, spacing: SpacingTokens.md) {
            Image(systemName: statusIcon(variant: variant))
                .font(.system(size: 28))
                .foregroundStyle(statusIconColor(variant: variant))

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                HStack(spacing: SpacingTokens.xs) {
                    Text(planTitle)
                        .font(TypographyTokens.headline)

                    StatusBadge(text: statusBadgeText(variant: variant), style: statusBadgeStyle(variant: variant))
                }

                Text(statusSubtitle(variant: variant))
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var planTitle: String {
        let tier = entitlementStore.currentPlanCode.tier
        switch tier {
        case .premium: return "ProEstimate Premium"
        case .pro: return "ProEstimate Pro"
        case .free: return "ProEstimate"
        }
    }

    private func statusIcon(variant: StatusVariant) -> String {
        switch variant {
        case .active: return "crown.fill"
        case .trial: return "sparkles"
        case .billingIssue: return "exclamationmark.triangle.fill"
        }
    }

    private func statusIconColor(variant: StatusVariant) -> Color {
        switch variant {
        case .active, .trial: return ColorTokens.primaryOrange
        case .billingIssue: return ColorTokens.warning
        }
    }

    private func statusBadgeText(variant: StatusVariant) -> String {
        switch variant {
        case .active:
            return entitlementStore.subscriptionState == .canceledActive ? "Canceled" : "Active"
        case .trial:
            if let days = entitlementStore.trialDaysRemaining, days > 0 {
                return days == 1 ? "Trial · 1 day left" : "Trial · \(days) days left"
            }
            return "Trial"
        case .billingIssue:
            return "Action needed"
        }
    }

    private func statusBadgeStyle(variant: StatusVariant) -> StatusBadge.Style {
        switch variant {
        case .active: return .success
        case .trial: return .info
        case .billingIssue: return .warning
        }
    }

    private func statusSubtitle(variant: StatusVariant) -> String {
        switch variant {
        case .active:
            if entitlementStore.subscriptionState == .canceledActive,
               let date = formattedRenewalDate
            {
                return "Access continues until \(date)."
            }
            if let date = formattedRenewalDate {
                return entitlementStore.isAutoRenewEnabled
                    ? "Renews \(date)."
                    : "Access through \(date)."
            }
            return "Unlimited AI previews, branded proposals, invoicing, and approvals."
        case .trial:
            if let date = formattedRenewalDate {
                return "Trial converts to paid on \(date). Cancel anytime in Settings."
            }
            return "Full access to every Pro feature during your trial."
        case .billingIssue:
            return entitlementStore.billingWarning
                ?? "Update your payment method to keep your subscription active."
        }
    }

    private var formattedRenewalDate: String? {
        guard let date = entitlementStore.renewalDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Free Upgrade Prompt

    private var upgradePromptContent: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            HStack(alignment: .top, spacing: SpacingTokens.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(ColorTokens.primaryOrange)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Get the Full ProEstimate AI")
                        .font(TypographyTokens.headline)
                    Text("Unlock AI previews, instant estimates, branded proposals, and lawn / roof scouting. Start a 7-day free trial.")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PrimaryCTAButton(title: "Start 7-Day Free Trial", icon: "crown") {
                onUpgrade?()
            }
        }
    }
}

// MARK: - Preview

#Preview("Free") {
    DashboardSubscriptionCard()
        .environment(EntitlementStore.preview(snapshot: .sampleFree))
        .padding()
}

#Preview("Pro Active") {
    DashboardSubscriptionCard()
        .environment(EntitlementStore.preview(snapshot: .samplePro))
        .padding()
}

#Preview("Grace Period") {
    DashboardSubscriptionCard()
        .environment(EntitlementStore.preview(snapshot: .sampleGracePeriod))
        .padding()
}
