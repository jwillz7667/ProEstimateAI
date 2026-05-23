import SwiftUI

/// Vertical list of in-flight quotes (Draft / Sent / Approved) under the
/// "Active Quotes" header on the Projects home tab. Tapping a row pushes
/// the Quote editor by switching to the Quotes tab and appending onto
/// `router.quotesPath` so deep navigation lands in the right stack.
struct ActiveQuotesSection: View {
    let quotes: [EstimateSummary]
    var onSelect: (EstimateSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            Text("Active Quotes")
                .font(TypographyTokens.title2)
                .foregroundStyle(ColorTokens.textPrimary)
                .padding(.horizontal, SpacingTokens.md)

            if quotes.isEmpty {
                emptyState
                    .padding(.horizontal, SpacingTokens.md)
            } else {
                VStack(spacing: SpacingTokens.sm) {
                    ForEach(quotes) { summary in
                        quoteRow(summary)
                    }
                }
                .padding(.horizontal, SpacingTokens.md)
            }
        }
    }

    // MARK: - Row

    private func quoteRow(_ summary: EstimateSummary) -> some View {
        Button {
            onSelect(summary)
        } label: {
            HStack(spacing: SpacingTokens.md) {
                quoteIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.projectTitle)
                        .font(TypographyTokens.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(1)

                    Text(subtitle(for: summary))
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                StatusBadge(text: statusLabel(for: summary.estimate.status), style: badgeStyle(for: summary.estimate.status))
            }
            .padding(.vertical, SpacingTokens.md)
            .padding(.horizontal, SpacingTokens.lg)
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary.projectTitle), \(statusLabel(for: summary.estimate.status))")
    }

    private var quoteIcon: some View {
        ZStack {
            Circle()
                .fill(ColorTokens.pillBackground)
                .frame(width: 44, height: 44)
            Image(systemName: "doc.text.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ColorTokens.pillForeground)
        }
    }

    // MARK: - Helpers

    private func subtitle(for summary: EstimateSummary) -> String {
        let amount = NSDecimalNumber(decimal: summary.estimate.totalAmount).doubleValue
        if amount > 0 {
            return formattedRange(amount: amount)
        }
        return "Pending Details"
    }

    /// Show the quote total as a soft "$45k – $55k" range for readability,
    /// matching the screenshot's "Est. $45k - $55k" treatment.
    private func formattedRange(amount: Double) -> String {
        let low = roundedThousands(amount * 0.9)
        let high = roundedThousands(amount * 1.1)
        return "Est. \(low) – \(high)"
    }

    private func roundedThousands(_ value: Double) -> String {
        guard value >= 1000 else {
            return String(format: "$%.0f", value)
        }
        let thousands = (value / 1000).rounded()
        return "$\(Int(thousands))k"
    }

    private func statusLabel(for status: Estimate.Status) -> String {
        switch status {
        case .draft: "Draft"
        case .sent: "Sent"
        case .approved: "Accepted"
        case .declined: "Declined"
        case .expired: "Expired"
        }
    }

    private func badgeStyle(for status: Estimate.Status) -> StatusBadge.Style {
        switch status {
        case .draft: .info
        case .sent: .accent
        case .approved: .success
        case .declined: .error
        case .expired: .neutral
        }
    }

    private var emptyState: some View {
        HStack(spacing: SpacingTokens.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 24))
                .foregroundStyle(ColorTokens.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("No active quotes")
                    .font(TypographyTokens.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Generate a vision and we'll help you turn it into a polished quote.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            Spacer()
        }
        .padding(SpacingTokens.lg)
        .glassCard()
    }
}
