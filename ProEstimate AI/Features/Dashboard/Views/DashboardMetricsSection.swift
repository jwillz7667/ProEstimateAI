import SwiftUI

/// Quiet business context beneath the project workflow, using real server
/// totals rather than inferring counts from Home's small project preview.
struct DashboardMetricsSection: View {
    let summary: DashboardSummary
    let formattedRevenue: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            Text("At a glance")
                .font(TypographyTokens.headline)
                .accessibilityAddTraits(.isHeader)

            metric("Invoices settled this month", value: formattedRevenue)
            Text("Total value of invoices marked paid. Partial payments are tracked on each invoice.")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            metricsLayout {
                metric("Active projects", value: summary.activeProjectsCount.formatted())
                metric("Invoices due", value: summary.invoicesDueCount.formatted())
            }
        }
        .padding(SpacingTokens.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
    }

    private var metricsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SpacingTokens.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: SpacingTokens.lg))
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text(value)
                .font(TypographyTokens.moneyMedium)
                .foregroundStyle(ColorTokens.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DashboardMetricsSection(summary: .sample, formattedRevenue: "$24,750")
        .padding()
        .background(ColorTokens.background)
}
