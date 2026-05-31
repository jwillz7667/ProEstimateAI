import SwiftUI

/// Non-blocking subscription status sheet. Mirrors the dark-glass aesthetic
/// of `PaywallHostView` but is purely informational — paying members can
/// always dismiss. Shows a celebratory snapshot of the active Pro plan and
/// everything it unlocks.
///
/// Reads the live `EntitlementStore` snapshot, so it stays in sync with
/// purchases / restores / `Transaction.updates` without explicit refresh.
struct SubscriptionStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementStore.self) private var entitlementStore

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: SpacingTokens.xl) {
                    hero
                        .padding(.top, SpacingTokens.xl)

                    FeatureComparisonListView()

                    primaryActions
                }
                .padding(.horizontal, SpacingTokens.lg)
                .padding(.bottom, SpacingTokens.xxxl)
            }

            dismissButton
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let tier = entitlementStore.currentPlanCode.tier
        return VStack(spacing: SpacingTokens.md) {
            tierMedallion(for: tier)

            VStack(spacing: SpacingTokens.xxs) {
                Text(tierTitle(for: tier))
                    .font(TypographyTokens.title2)
                    .foregroundStyle(ColorTokens.primaryText)
                    .multilineTextAlignment(.center)

                Text(tierSubtitle(for: tier))
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tierMedallion(for tier: PlanTier) -> some View {
        ZStack {
            Circle()
                .fill(tierGradient(for: tier))
                .frame(width: 96, height: 96)
                .shadow(color: tierShadowColor(for: tier).opacity(0.45), radius: 18, x: 0, y: 8)

            Image(systemName: tierIconName(for: tier))
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Primary Actions

    @ViewBuilder
    private var primaryActions: some View {
        // Pro is the only subscriber tier; free users wouldn't normally
        // reach this view (the badge is hidden) but the button is a safe
        // fallback if the snapshot is mid-flight or this is a preview.
        doneButton
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(TypographyTokens.headline)
                .foregroundStyle(ColorTokens.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpacingTokens.md)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.button)
                        .strokeBorder(ColorTokens.subtleBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tier Styling

    private func tierIconName(for tier: PlanTier) -> String {
        switch tier {
        case .free: return "sparkles"
        case .pro: return "checkmark.seal.fill"
        }
    }

    private func tierGradient(for tier: PlanTier) -> LinearGradient {
        switch tier {
        case .free:
            return LinearGradient(
                colors: [ColorTokens.primaryOrange, ColorTokens.primaryOrange.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pro:
            return LinearGradient(
                colors: [ColorTokens.primaryOrange, Color(hex: 0xEA580C)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func tierShadowColor(for tier: PlanTier) -> Color {
        switch tier {
        case .free, .pro: return ColorTokens.primaryOrange
        }
    }

    private func tierTitle(for tier: PlanTier) -> String {
        switch tier {
        case .free: return "Free Plan"
        case .pro:
            if entitlementStore.isTrial { return "You're on a Pro Trial" }
            return "You're a Pro Member"
        }
    }

    private func tierSubtitle(for tier: PlanTier) -> String {
        if let renewal = entitlementStore.renewalDate {
            let when = renewal.formatted(as: .medium)
            switch tier {
            case .free: return "Subscribe to unlock the full toolkit."
            case .pro:
                return entitlementStore.isAutoRenewEnabled
                    ? "Subscription active · renews \(when)"
                    : "Subscription active · ends \(when)"
            }
        }
        switch tier {
        case .free: return "Subscribe to unlock the full toolkit."
        case .pro: return "Your subscription is active."
        }
    }

    // MARK: - Background

    /// Adaptive backdrop matching the rest of the paywall surface — white
    /// in light mode, system-dark in dark mode — so the status sheet
    /// reads as part of the host theme rather than an always-dark hero.
    private var backgroundGradient: some View {
        ZStack {
            ColorTokens.background
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    ColorTokens.primaryOrange.opacity(0.06),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ColorTokens.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, SpacingTokens.md)
                .padding(.top, SpacingTokens.md)
                .accessibilityLabel("Close")
                .accessibilityHint("Dismiss the subscription status page")
            }
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Pro") {
    SubscriptionStatusView()
        .environment(EntitlementStore.preview(snapshot: .samplePro))
}
