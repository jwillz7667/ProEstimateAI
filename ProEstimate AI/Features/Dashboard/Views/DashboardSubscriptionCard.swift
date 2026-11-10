import SwiftUI

/// Secondary plan information. Purchase offers remain in the paywall, where
/// StoreKit supplies the actual price and trial eligibility.
struct DashboardSubscriptionCard: View {
    @Environment(EntitlementStore.self) private var entitlementStore
    var onUpgrade: (() -> Void)?
    var onManage: (() -> Void)?

    var body: some View {
        if entitlementStore.snapshot == nil {
            Button { onManage?() } label: {
                content(title: "Plan details", subtitle: "View your subscription in Settings.", icon: "person.crop.circle")
            }
            .buttonStyle(.plain)
        } else {
            Button {
                if entitlementStore.hasProAccess || entitlementStore.hasBillingIssue {
                    onManage?()
                } else {
                    onUpgrade?()
                }
            } label: {
                content(title: title, subtitle: subtitle, icon: icon)
            }
            .buttonStyle(.plain)
            .accessibilityHint(entitlementStore.hasProAccess || entitlementStore.hasBillingIssue
                ? "Opens subscription settings" : "View Pro plans, pricing and trial eligibility")
        }
    }

    private func content(title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: SpacingTokens.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(ColorTokens.primaryText)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(title)
                    .font(TypographyTokens.subheadline.weight(.semibold))
                    .foregroundStyle(ColorTokens.primaryText)
                Text(subtitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ColorTokens.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, SpacingTokens.md)
        .padding(.horizontal, SpacingTokens.xxs)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch entitlementStore.subscriptionState {
        case .free, .expired, .revoked: "AI tools with Pro"
        case .trialActive: "Pro trial active"
        case .gracePeriod, .billingRetry: "Billing needs attention"
        case .proActive, .canceledActive, .adminOverride: "Pro plan"
        }
    }

    private var icon: String {
        if entitlementStore.hasBillingIssue { return "exclamationmark.triangle" }
        return entitlementStore.hasProAccess ? "checkmark.seal" : "sparkles"
    }

    private var subtitle: String {
        switch entitlementStore.subscriptionState {
        case .free, .expired, .revoked:
            return "Basic project tools stay free. View Pro plans for AI previews and estimates."
        case .trialActive:
            if let date = entitlementStore.snapshot?.trialEndsAt {
                if entitlementStore.isAccountTrial {
                    return "Included until \(date.formatted(date: .abbreviated, time: .omitted)). No automatic charge."
                }
                return "Trial ends \(date.formatted(date: .abbreviated, time: .omitted)). View plan details."
            }
            return "View your trial and plan details."
        case .gracePeriod, .billingRetry:
            return "Review your payment method in subscription settings."
        case .canceledActive:
            if let date = entitlementStore.renewalDate {
                return "Access until \(date.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Subscription canceled. Access continues until your paid period ends."
        case .proActive, .adminOverride:
            if let bucket = entitlementStore.snapshot?.usage.first(where: { $0.metricCode == .aiGeneration }) {
                return "\(bucket.remainingQuantity) AI previews left in your plan window."
            }
            return "View your included tools and plan details."
        }
    }
}

#Preview("Free") {
    DashboardSubscriptionCard()
        .environment(EntitlementStore.preview(snapshot: .sampleFree))
        .padding()
}

#Preview("Pro") {
    DashboardSubscriptionCard()
        .environment(EntitlementStore.preview(snapshot: .samplePro))
        .padding()
}

#Preview("Billing issue") {
    DashboardSubscriptionCard()
        .environment(EntitlementStore.preview(snapshot: .sampleGracePeriod))
        .padding()
}
