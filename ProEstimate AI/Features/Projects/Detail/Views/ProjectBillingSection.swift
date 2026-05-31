import SwiftUI

/// Lists the proposals and invoices generated from this project's estimates —
/// the back half of the get-paid loop. Each row is tappable so the contractor
/// can re-open a proposal to resend / copy its share link, or an invoice to
/// send it and mark it paid. Hidden entirely when neither exists, so a project
/// that hasn't reached the proposal/invoice stage doesn't grow an empty card.
struct ProjectBillingSection: View {
    let proposals: [Proposal]
    let invoices: [Invoice]
    var onTapProposal: ((Proposal) -> Void)?
    var onTapInvoice: ((Invoice) -> Void)?

    var body: some View {
        if !proposals.isEmpty || !invoices.isEmpty {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                SectionHeaderView(title: "Proposals & Invoices")

                VStack(spacing: SpacingTokens.sm) {
                    ForEach(proposals) { proposal in
                        Button {
                            onTapProposal?(proposal)
                        } label: {
                            proposalRow(proposal)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(invoices) { invoice in
                        Button {
                            onTapInvoice?(invoice)
                        } label: {
                            invoiceRow(invoice)
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
                icon("doc.richtext", tint: ColorTokens.primaryOrange)

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

    private func invoiceRow(_ invoice: Invoice) -> some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                icon("dollarsign.circle.fill", tint: ColorTokens.success)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(invoice.invoiceNumber)
                        .font(TypographyTokens.headline)
                        .lineLimit(1)
                    HStack(spacing: SpacingTokens.xxs) {
                        StatusBadge(text: invoiceStatusName(invoice.status), style: invoiceStatusStyle(invoice.status))
                        if invoice.isOutstanding, let due = invoice.dueDate {
                            Text("Due \(due.formatted(as: .invoiceDate))")
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                CurrencyText(amount: invoice.totalAmount, font: TypographyTokens.moneySmall)
            }
        }
    }

    private func icon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.small))
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

    private func invoiceStatusName(_ status: Invoice.Status) -> String {
        switch status {
        case .draft: "Draft"
        case .sent: "Sent"
        case .viewed: "Viewed"
        case .partiallyPaid: "Partially Paid"
        case .paid: "Paid"
        case .overdue: "Overdue"
        case .void: "Void"
        }
    }

    private func invoiceStatusStyle(_ status: Invoice.Status) -> StatusBadge.Style {
        switch status {
        case .draft: .neutral
        case .sent, .viewed: .info
        case .partiallyPaid: .warning
        case .paid: .success
        case .overdue: .error
        case .void: .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProjectBillingSection(proposals: [.sample], invoices: [.sample])
    }
}
