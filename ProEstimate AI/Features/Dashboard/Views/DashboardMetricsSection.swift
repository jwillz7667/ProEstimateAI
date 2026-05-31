import SwiftUI

/// Top-of-dashboard business snapshot: revenue this month, invoices awaiting
/// payment, active projects, and pending estimates. Sourced from the backend's
/// `/v1/dashboard` summary. Reloads whenever a payment event fires (an invoice
/// is marked paid), so "Revenue this month" reflects the get-paid loop's
/// outcome without a manual refresh.
struct DashboardMetricsSection: View {
    let summary: DashboardSummary
    /// Pre-formatted currency string from the view model so the section stays
    /// presentation-only and locale handling lives in one place.
    let formattedRevenue: String

    private let columns = [
        GridItem(.flexible(), spacing: SpacingTokens.sm),
        GridItem(.flexible(), spacing: SpacingTokens.sm),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: SpacingTokens.sm) {
            MetricCard(
                label: "Revenue This Month",
                value: formattedRevenue
            )
            MetricCard(
                label: "Invoices Due",
                value: "\(summary.invoicesDueCount)",
                trend: summary.invoicesDueCount > 0
                    ? .neutral(summary.invoicesDueCount == 1 ? "1 awaiting payment" : "\(summary.invoicesDueCount) awaiting payment")
                    : nil
            )
            MetricCard(
                label: "Active Projects",
                value: "\(summary.activeProjectsCount)"
            )
            MetricCard(
                label: "Pending Estimates",
                value: "\(summary.pendingEstimatesCount)"
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DashboardMetricsSection(summary: .sample, formattedRevenue: "$24,750")
            .padding()
    }
}
