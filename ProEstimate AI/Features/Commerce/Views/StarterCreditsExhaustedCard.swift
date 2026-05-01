import SwiftUI

/// Counter card surfaced ONLY on the `.generationLimitHit` paywall.
///
/// The free-tier starter credit count is intentionally hidden from
/// every other surface (dashboard, project detail, settings) so the
/// app reads as "fully open" until the user actually exhausts their
/// pool. At that moment the paywall fires and this card explains why
/// — "You've used all 5 of your free generations" — alongside the
/// usual upgrade CTAs.
///
/// Reads from `UsageMeterStore.shared` so the displayed total reflects
/// whatever the backend actually issued (the iOS constant is just a
/// fallback). Defaults gracefully if the store hasn't been populated.
struct StarterCreditsExhaustedCard: View {
    @State private var meter = UsageMeterStore.shared

    /// Whether to render the card at all. Returns false outside the
    /// generation-limit-hit context so the same view can be dropped
    /// into a paywall composition without per-placement branching at
    /// the parent level.
    var isVisible: Bool

    /// Total starter credits the backend issued. Falls back to the
    /// canonical iOS constant if the meter hasn't been hydrated yet.
    private var includedTotal: Int {
        let total = meter.generationsTotal
        guard total > 0, total != Int.max else {
            return AppConstants.freeGenerationCredits
        }
        return total
    }

    var body: some View {
        if isVisible {
            HStack(spacing: SpacingTokens.md) {
                ZStack {
                    Circle()
                        .fill(ColorTokens.primaryOrange.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ColorTokens.primaryOrange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Generations Used")
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(ColorTokens.primaryText)

                    Text("\(includedTotal) of \(includedTotal) generations spent")
                        .font(TypographyTokens.footnote)
                        .foregroundStyle(ColorTokens.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(SpacingTokens.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                    .fill(ColorTokens.primaryOrange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("All \(includedTotal) free AI generations used. Subscribe to keep generating.")
        }
    }
}

#Preview {
    StarterCreditsExhaustedCard(isVisible: true)
        .padding()
        .background(ColorTokens.background)
}
