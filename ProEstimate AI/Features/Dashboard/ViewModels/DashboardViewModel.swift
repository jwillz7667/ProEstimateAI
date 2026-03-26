import Foundation
import Observation

@Observable
final class DashboardViewModel {
    // MARK: - Published state

    var summary: DashboardSummary?
    var recentProjects: [Project] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    /// Greeting based on time of day.
    func greeting(for name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 0..<12:
            timeGreeting = "Good morning"
        case 12..<17:
            timeGreeting = "Good afternoon"
        default:
            timeGreeting = "Good evening"
        }
        return "\(timeGreeting), \(name.components(separatedBy: " ").first ?? name)"
    }

    /// Formatted revenue string for the metric card.
    var formattedRevenue: String {
        guard let revenue = summary?.revenueThisMonth else { return "$0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: revenue as NSDecimalNumber) ?? "$0"
    }

    // MARK: - Actions

    func loadDashboard() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Simulate network delay
        do {
            try await Task.sleep(for: .seconds(0.6))
        } catch {
            // Task cancelled
            isLoading = false
            return
        }

        summary = DashboardSummary.sample
        recentProjects = Self.sampleProjects
        isLoading = false
    }

    func refresh() async {
        await loadDashboard()
    }

    // MARK: - Sample Projects

    private static let sampleProjects: [Project] = [
        Project(
            id: "p-001",
            companyId: "c-001",
            clientId: "cl-001",
            title: "Kitchen Remodel - Mitchell",
            description: "Full kitchen remodel with new cabinets and island.",
            projectType: .kitchen,
            status: .estimateCreated,
            budgetMin: 15000,
            budgetMax: 35000,
            qualityTier: .premium,
            squareFootage: 250,
            dimensions: "20x12.5",
            language: "en",
            createdAt: Date().addingTimeInterval(-86400 * 2),
            updatedAt: Date().addingTimeInterval(-3600)
        ),
        Project(
            id: "p-002",
            companyId: "c-001",
            clientId: "cl-002",
            title: "Bathroom Renovation - Chen",
            description: "Master bath renovation with walk-in shower.",
            projectType: .bathroom,
            status: .proposalSent,
            budgetMin: 8000,
            budgetMax: 18000,
            qualityTier: .premium,
            squareFootage: 80,
            dimensions: "10x8",
            language: "en",
            createdAt: Date().addingTimeInterval(-86400 * 5),
            updatedAt: Date().addingTimeInterval(-86400)
        ),
        Project(
            id: "p-003",
            companyId: "c-001",
            clientId: "cl-003",
            title: "Hardwood Flooring - Davis",
            description: "Install engineered hardwood throughout first floor.",
            projectType: .flooring,
            status: .approved,
            budgetMin: 6000,
            budgetMax: 12000,
            qualityTier: .standard,
            squareFootage: 1200,
            dimensions: nil,
            language: "en",
            createdAt: Date().addingTimeInterval(-86400 * 10),
            updatedAt: Date().addingTimeInterval(-86400 * 2)
        ),
        Project(
            id: "p-004",
            companyId: "c-001",
            clientId: "cl-004",
            title: "Exterior Painting - Wallace",
            description: "Full exterior repaint, two-story colonial.",
            projectType: .painting,
            status: .draft,
            budgetMin: 4000,
            budgetMax: 8000,
            qualityTier: .standard,
            squareFootage: nil,
            dimensions: nil,
            language: "en",
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date().addingTimeInterval(-3600 * 4)
        ),
        Project(
            id: "p-005",
            companyId: "c-001",
            clientId: "cl-005",
            title: "Roof Replacement - Nguyen",
            description: "Tear off and replace asphalt shingle roof.",
            projectType: .roofing,
            status: .invoiced,
            budgetMin: 10000,
            budgetMax: 20000,
            qualityTier: .premium,
            squareFootage: 2400,
            dimensions: nil,
            language: "en",
            createdAt: Date().addingTimeInterval(-86400 * 14),
            updatedAt: Date().addingTimeInterval(-86400 * 3)
        ),
    ]
}
