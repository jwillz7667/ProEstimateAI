import SwiftUI

/// Lists estimates linked to this project. Each row shows the estimate
/// number, version, total amount, and status badge. Exposes a single
/// primary "Generate Estimate" CTA that uses AI with any selected
/// materials as context; a secondary menu houses the blank-estimate
/// escape hatch for power users who want to start from scratch.
struct ProjectEstimatesSection: View {
    let estimates: [Estimate]
    var isGeneratingAI: Bool = false
    var onGenerateAI: (() -> Void)?
    var onCreateEstimate: (() -> Void)?
    var onEstimateTap: ((String) -> Void)?

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

            // One primary action. Users who explicitly want an empty
            // estimate can reach it via the overflow menu.
            VStack(spacing: SpacingTokens.xs) {
                PrimaryCTAButton(
                    title: estimates.isEmpty ? "Generate Estimate" : "Generate New Estimate",
                    icon: "wand.and.stars",
                    isLoading: isGeneratingAI,
                    isDisabled: isGeneratingAI
                ) {
                    onGenerateAI?()
                }

                Menu {
                    Button {
                        onCreateEstimate?()
                    } label: {
                        Label("Start from blank estimate", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Text("More options")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, SpacingTokens.xxs)
                }
                .disabled(isGeneratingAI)
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    // MARK: - Subviews

    private var estimatesList: some View {
        VStack(spacing: SpacingTokens.xs) {
            ForEach(estimates) { estimate in
                Button {
                    onEstimateTap?(estimate.id)
                } label: {
                    estimateRow(estimate)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        onEstimateTap?(estimate.id)
                    } label: {
                        Label("Edit Estimate", systemImage: "pencil")
                    }
                }
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
                            .background(ColorTokens.inputBackground, in: Capsule())
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
