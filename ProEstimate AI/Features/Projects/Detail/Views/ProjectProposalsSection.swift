import SwiftUI

/// Lists the proposals generated from this project's estimates — the approval
/// half of the get-paid loop. Each row is tappable so the contractor can
/// re-open a proposal to resend or copy its share link. Invoices now live in
/// their own top-level tab; estimates convert to invoices via the estimate row
/// action. Hidden entirely when no proposals exist, so a project that hasn't
/// reached the proposal stage doesn't grow an empty card.
struct ProjectProposalsSection: View {
    let proposals: [Proposal]
    var onTapProposal: ((Proposal) -> Void)?

    var body: some View {
        if !proposals.isEmpty {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                SectionHeaderView(title: "Proposals")

                VStack(spacing: SpacingTokens.sm) {
                    ForEach(proposals) { proposal in
                        Button {
                            onTapProposal?(proposal)
                        } label: {
                            proposalRow(proposal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SpacingTokens.md)
            }
        }
    }

    // MARK: - Rows

    private func proposalRow(_ proposal: Proposal) -> some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 36, height: 36)
                    .background(ColorTokens.primaryOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.small))

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(proposal.displayTitle)
                        .font(TypographyTokens.headline)
                        .lineLimit(1)
                    Text(proposal.createdAt.formatted(as: .relative))
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                StatusBadge(text: proposalStatusName(proposal.status), style: proposalStatusStyle(proposal.status))
            }
        }
    }

    // MARK: - Status Presentation

    private func proposalStatusName(_ status: Proposal.Status) -> String {
        switch status {
        case .draft: "Draft"
        case .sent: "Sent"
        case .viewed: "Viewed"
        case .approved: "Approved"
        case .declined: "Declined"
        case .expired: "Expired"
        }
    }

    private func proposalStatusStyle(_ status: Proposal.Status) -> StatusBadge.Style {
        switch status {
        case .draft: .neutral
        case .sent: .info
        case .viewed: .warning
        case .approved: .success
        case .declined: .error
        case .expired: .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProjectProposalsSection(proposals: [.sample])
    }
}
