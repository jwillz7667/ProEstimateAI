import SwiftUI

/// Lists estimates linked to this project. Each row shows the estimate
/// number, version, total amount, and status badge. Includes a
/// "Create Estimate" button.
struct ProjectEstimatesSection: View {
    let estimates: [Estimate]

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(
                title: "Estimates",
                actionTitle: estimates.isEmpty ? nil : "\(estimates.count) version\(estimates.count == 1 ? "" : "s")"
            )

            if estimates.isEmpty {
                emptyView
            } else {
                estimatesList
            }

            // Create estimate button
            SecondaryButton(title: "Create Estimate", icon: "doc.badge.plus") {
                // Navigate to estimate editor (future phase)
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    // MARK: - Subviews

    private var estimatesList: some View {
        VStack(spacing: SpacingTokens.xs) {
            ForEach(estimates) { estimate in
                estimateRow(estimate)
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    private func estimateRow(_ estimate: Estimate) -> some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                // Estimate icon
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 36, height: 36)
                    .background(ColorTokens.primaryOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.small))

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    HStack(spacing: SpacingTokens.xs) {
                        Text(estimate.estimateNumber)
                            .font(TypographyTokens.headline)

                        Text("v\(estimate.version)")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, SpacingTokens.xxs)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15), in: Capsule())
                    }

                    HStack(spacing: SpacingTokens.xs) {
                        estimateStatusBadge(estimate.status)

                        Spacer()

                        Text(estimate.createdAt.formatted(as: .relative))
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                CurrencyText(amount: estimate.totalAmount, font: TypographyTokens.moneySmall)
            }
        }
    }

    private func estimateStatusBadge(_ status: Estimate.Status) -> some View {
        let (text, style): (String, StatusBadge.Style) = {
            switch status {
            case .draft: ("Draft", .neutral)
            case .sent: ("Sent", .info)
            case .approved: ("Approved", .success)
            case .declined: ("Declined", .error)
            case .expired: ("Expired", .warning)
            }
        }()

        return StatusBadge(text: text, style: style)
    }

    private var emptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No estimates yet")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
            Text("Create an estimate from AI-suggested materials or start from scratch.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SpacingTokens.xl)
        .padding(.horizontal, SpacingTokens.md)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProjectEstimatesSection(estimates: MockGenerationService.sampleEstimates)
    }
}
