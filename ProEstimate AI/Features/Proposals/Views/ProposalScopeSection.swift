import SwiftUI

struct ProposalScopeSection: View {
    let project: Project?
    let estimate: Estimate?
    let materialItemCount: Int
    let laborItemCount: Int
    let otherItemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            Text("Scope of Work")
                .font(TypographyTokens.title3)

            // Project details
            if let project {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    if let description = project.description {
                        Text(description)
                            .font(TypographyTokens.body)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: SpacingTokens.lg) {
                        detailPill(icon: "house", label: project.projectType.rawValue.capitalized)
                        detailPill(icon: "star", label: project.qualityTier.rawValue.capitalized)

                        if let sqft = project.squareFootage {
                            detailPill(
                                icon: "ruler",
                                label: "\(NSDecimalNumber(decimal: sqft).intValue) sq ft"
                            )
                        }
                    }
                }
            }

            Divider()

            // Scope categories
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text("Included in this proposal:")
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)

                if materialItemCount > 0 {
                    scopeItem(
                        icon: "shippingbox",
                        color: ColorTokens.primaryOrange,
                        text: "\(materialItemCount) material item\(materialItemCount == 1 ? "" : "s")"
                    )
                }

                if laborItemCount > 0 {
                    scopeItem(
                        icon: "hammer",
                        color: .blue,
                        text: "\(laborItemCount) labor item\(laborItemCount == 1 ? "" : "s")"
                    )
                }

                if otherItemCount > 0 {
                    scopeItem(
                        icon: "ellipsis.circle",
                        color: .purple,
                        text: "\(otherItemCount) additional item\(otherItemCount == 1 ? "" : "s")"
                    )
                }
            }

            // Valid until
            if let validUntil = estimate?.validUntil {
                Divider()

                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(ColorTokens.warning)
                    Text("Valid until \(validUntil.formatted(as: .long))")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(SpacingTokens.lg)
    }

    // MARK: - Subviews

    private func detailPill(icon: String, label: String) -> some View {
        HStack(spacing: SpacingTokens.xxs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(TypographyTokens.caption)
        }
        .padding(.horizontal, SpacingTokens.xs)
        .padding(.vertical, SpacingTokens.xxs)
        .background(Color.gray.opacity(0.1), in: Capsule())
        .foregroundStyle(.secondary)
    }

    private func scopeItem(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: SpacingTokens.xs) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(TypographyTokens.body)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProposalScopeSection(
            project: .sample,
            estimate: .sample,
            materialItemCount: 3,
            laborItemCount: 2,
            otherItemCount: 1
        )
    }
}
