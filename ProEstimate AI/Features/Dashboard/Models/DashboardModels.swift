import Foundation

/// Aggregated summary data for the dashboard home screen.
struct DashboardSummary: Codable, Sendable {
    let activeProjectsCount: Int
    let pendingEstimatesCount: Int
    let revenueThisMonth: Decimal
    let invoicesDueCount: Int
    let generationsRemaining: Int
    let quotesRemaining: Int

    enum CodingKeys: String, CodingKey {
        case activeProjectsCount = "active_projects_count"
        case pendingEstimatesCount = "pending_estimates_count"
        case revenueThisMonth = "revenue_this_month"
        case invoicesDueCount = "invoices_due_count"
        case generationsRemaining = "generations_remaining"
        case quotesRemaining = "quotes_remaining"
    }
}

// MARK: - Sample Data

extension DashboardSummary {
    static let sample = DashboardSummary(
        activeProjectsCount: 7,
        pendingEstimatesCount: 3,
        revenueThisMonth: 24_750.00,
        invoicesDueCount: 2,
        generationsRemaining: 2,
        quotesRemaining: 1
    )

    static let empty = DashboardSummary(
        activeProjectsCount: 0,
        pendingEstimatesCount: 0,
        revenueThisMonth: 0,
        invoicesDueCount: 0,
        generationsRemaining: AppConstants.freeGenerationCredits,
        quotesRemaining: AppConstants.freeQuoteExportCredits
    )
}

// MARK: - Quick Action

enum QuickAction: String, CaseIterable, Identifiable {
    case newProject
    case newClient
    case viewEstimates
    case viewInvoices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newProject: "New Project"
        case .newClient: "New Client"
        case .viewEstimates: "Estimates"
        case .viewInvoices: "Invoices"
        }
    }

    var icon: String {
        switch self {
        case .newProject: "folder.badge.plus"
        case .newClient: "person.badge.plus"
        case .viewEstimates: "doc.text"
        case .viewInvoices: "dollarsign.circle"
        }
    }
}
