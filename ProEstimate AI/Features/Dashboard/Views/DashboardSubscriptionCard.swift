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

    private var freeContent: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            HStack {
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Free Plan")
                        .font(TypographyTokens.headline)

                    Text("Upgrade to Pro for unlimited access")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                }

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(ColorTokens.primaryOrange)
            }

            // AI Generations progress
            creditRow(
                label: "AI Generations",
                remaining: generationsRemaining,
                total: AppConstants.freeGenerationCredits
            )

            // Quote Exports progress
            creditRow(
                label: "Quote Exports",
                remaining: quotesRemaining,
                total: AppConstants.freeQuoteExportCredits
            )

            PrimaryCTAButton(title: "Upgrade to Pro", icon: "crown") {
                onUpgrade?()
            }
        }
    }

    // MARK: - Credit Row

    private func creditRow(label: String, remaining: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            HStack {
                Text(label)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)

                Spacer()

                Text("\(remaining)/\(total) remaining")
                    .font(TypographyTokens.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(remaining > 0 ? ColorTokens.primaryOrange : ColorTokens.error)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorTokens.progressTrack)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(remaining > 0 ? ColorTokens.primaryOrange : ColorTokens.error)
                        .frame(
                            width: geometry.size.width * CGFloat(remaining) / CGFloat(max(total, 1)),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
        }
    }
}
