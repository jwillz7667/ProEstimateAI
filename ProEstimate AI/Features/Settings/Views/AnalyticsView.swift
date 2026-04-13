import SwiftUI

struct AnalyticsView: View {
    @State private var summary: DashboardSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    var body: some View {
        Group {
            if isLoading && summary == nil {
                LoadingStateView(message: "Loading analytics...")
            } else if let errorMessage, summary == nil {
                RetryStateView(message: errorMessage) {
                    Task { await loadSummary() }
                }
            } else {
                ScrollView {
                    VStack(spacing: SpacingTokens.lg) {
                        metricsGrid
                    }
                    .padding(SpacingTokens.md)
                }
            }
        }
        .navigationTitle("Analytics")
        .task {
            await loadSummary()
        }
    }

    private var metricsGrid: some View {
        let data = summary ?? DashboardSummary.empty
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SpacingTokens.sm),
                GridItem(.flexible(), spacing: SpacingTokens.sm),
            ],
            spacing: SpacingTokens.sm
        ) {
            MetricCard(
                label: "Active Projects",
                value: "\(data.activeProjectsCount)"
            )

            MetricCard(
                label: "Pending Estimates",
                value: "\(data.pendingEstimatesCount)"
            )

            MetricCard(
                label: "Revenue This Month",
                value: formattedRevenue
            )

            MetricCard(
                label: "Invoices Due",
                value: "\(data.invoicesDueCount)"
            )
        }
    }

    private var formattedRevenue: String {
        guard let revenue = summary?.revenueThisMonth else { return "$0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: revenue as NSDecimalNumber) ?? "$0"
    }

    private func loadSummary() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await apiClient.request(.getDashboardSummary)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
