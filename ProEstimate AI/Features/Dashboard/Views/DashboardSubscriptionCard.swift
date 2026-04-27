import SwiftUI

/// Shows the user's subscription status on the dashboard.
/// For free-tier users, displays remaining AI generation credits and an upgrade CTA.
/// For Pro subscribers, shows the active badge.
struct DashboardSubscriptionCard: View {
    let generationsRemaining: Int
    let quotesRemaining: Int
    let isPro: Bool
    var onUpgrade: (() -> Void)?

    init(
        generationsRemaining: Int = AppConstants.freeGenerationCredits,
        quotesRemaining: Int = AppConstants.freeQuoteExportCredits,
        isPro: Bool = false,
        onUpgrade: (() -> Void)? = nil
    ) {
        self.generationsRemaining = generationsRemaining
        self.quotesRemaining = quotesRemaining
        self.isPro = isPro
        self.onUpgrade = onUpgrade
    }

    var body: some View {
        GlassCard {
            if isPro {
                proContent
            } else {
                freeContent
            }
        }
    }

    // MARK: - Pro Content

    private var proContent: some View {
        HStack(spacing: SpacingTokens.md) {
            Image(systemName: "crown.fill")
                .font(.system(size: 28))
                .foregroundStyle(ColorTokens.primaryOrange)

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                HStack(spacing: SpacingTokens.xs) {
                    Text("ProEstimate Pro")
                        .font(TypographyTokens.headline)

                    StatusBadge(text: "Active", style: .success)
                }

                Text("Unlimited AI generations and exports")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
            }

            Spacer()
        }
    }

    // MARK: - Free Content

    /// Free users see no credit progress bars (the "3 free previews"
    /// model is gone). The card is now a clean upgrade CTA — every paid
    /// action route gates them to the same paywall on first tap.
    private var freeContent: some View {
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
