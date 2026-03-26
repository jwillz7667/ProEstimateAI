import Foundation
import Observation

@Observable
final class EstimateListViewModel {
    // MARK: - Dependencies

    private let service: EstimateServiceProtocol

    // MARK: - State

    var estimates: [EstimateSummary] = []
    var searchText: String = ""
    var selectedFilter: EstimateStatusFilter = .all
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    /// Filtered and searched estimates for display.
    var filteredEstimates: [EstimateSummary] {
        var result = estimates

        // Apply status filter
        if selectedFilter != .all {
            let matchingStatuses = selectedFilter.matchingStatuses
            result = result.filter { matchingStatuses.contains($0.estimate.status) }
        }

        // Apply search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { summary in
                summary.estimate.estimateNumber.lowercased().contains(query)
                    || summary.projectTitle.lowercased().contains(query)
            }
        }

        return result
    }

    /// Count of estimates per status for filter badges.
    var draftCount: Int { estimates.filter { $0.estimate.status == .draft }.count }
    var sentCount: Int { estimates.filter { $0.estimate.status == .sent }.count }
    var approvedCount: Int { estimates.filter { $0.estimate.status == .approved }.count }

    // MARK: - Init

    init(service: EstimateServiceProtocol = MockEstimateService()) {
        self.service = service
    }

    // MARK: - Actions

    func loadEstimates() async {
        isLoading = true
        errorMessage = nil
        do {
            estimates = try await service.listEstimates()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteEstimate(id: String) async {
        do {
            try await service.deleteEstimate(id: id)
            estimates.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
