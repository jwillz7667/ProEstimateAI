import SwiftUI

/// Prominent card shown on the project detail page when the backend
/// has auto-created an estimate after AI generation completes.
/// Displays the estimate total and a CTA to review it in the editor.
struct AIEstimateReadyCard: View {
    let estimate: Estimate
    let onReview: () -> Void

    var body: some View {
        GlassCard {
            VStack(spacing: SpacingTokens.sm) {
                HStack(spacing: SpacingTokens.sm) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(ColorTokens.primaryOrange)
                        .frame(width: 40, height: 40)
                        .background(
                            ColorTokens.primaryOrange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                        )

                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text("AI Estimate Ready")
                            .font(TypographyTokens.headline)

                        Text(estimate.estimateNumber)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    CurrencyText(amount: estimate.totalAmount, font: TypographyTokens.moneyMedium)
                        .foregroundStyle(ColorTokens.success)
                }

                HStack(spacing: SpacingTokens.xs) {
                    if estimate.subtotalMaterials > 0 {
                        Label {
                            Text("Materials: ")
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                            + Text(formattedCurrency(estimate.subtotalMaterials))
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "shippingbox")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if estimate.subtotalLabor > 0 {
                        Label {
                            Text("Labor: ")
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                            + Text(formattedCurrency(estimate.subtotalLabor))
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "hammer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                PrimaryCTAButton(
                    title: "Review Estimate",
                    icon: "doc.text.magnifyingglass"
                ) {
                    onReview()
                }
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    private func formattedCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0"
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        AIEstimateReadyCard(
            estimate: .sample,
            onReview: {}
        )
    }
}
