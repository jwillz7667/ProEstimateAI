import Foundation
import Observation

@Observable
final class ProposalViewModel {
    // MARK: - Dependencies

    private let service: ProposalServiceProtocol

    // MARK: - State

    var proposal: Proposal?
    var estimate: Estimate?
    var lineItems: [EstimateLineItem] = []
    var project: Project?
    var client: Client?
    var company: Company?

    var isLoading: Bool = false
    var isSending: Bool = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Computed

    /// Line items grouped by category for the estimate table.
    var materialLineItems: [EstimateLineItem] {
        lineItems.filter { $0.category == .materials }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var laborLineItems: [EstimateLineItem] {
        lineItems.filter { $0.category == .labor }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var otherLineItems: [EstimateLineItem] {
        lineItems.filter { $0.category == .other }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Formatted proposal date for display.
    var formattedDate: String {
        let date = proposal?.createdAt ?? Date()
        return date.formatted(as: .long)
    }

    /// Formatted expiration date.
    var formattedExpiryDate: String? {
        guard let expiresAt = proposal?.expiresAt else { return nil }
        return expiresAt.formatted(as: .long)
    }

    /// Company full address.
    var companyAddress: String? {
        guard let company else { return nil }
        let parts = [company.address, company.city, company.state, company.zip].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    /// Client full address.
    var clientAddress: String? {
        client?.formattedAddress
    }

    /// Shareable URL for this proposal.
    var shareURL: URL? {
        proposal?.shareURL
    }

    /// Whether the proposal can be sent.
    var canSend: Bool {
        proposal?.status == .draft
    }

    /// Status badge style for the proposal.
    var statusBadgeStyle: StatusBadge.Style {
        guard let status = proposal?.status else { return .neutral }
        switch status {
        case .draft: return .neutral
        case .sent: return .info
        case .viewed: return .warning
        case .approved: return .success
        case .declined: return .error
        case .expired: return .warning
        }
    }

    // MARK: - Init

    init(service: ProposalServiceProtocol = MockProposalService()) {
        self.service = service
    }

    // MARK: - Actions

    func loadProposal(id: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedProposal = try await service.getProposal(id: id)
            proposal = loadedProposal

            // Load all related data in parallel
            async let estimateTask = service.getProposalEstimate(proposalId: loadedProposal.id)
            async let projectTask = service.getProposalProject(projectId: loadedProposal.projectId)
            async let companyTask = service.getProposalCompany(companyId: loadedProposal.companyId)

            let (loadedEstimate, loadedProject, loadedCompany) = try await (
                estimateTask, projectTask, companyTask
            )

            estimate = loadedEstimate
            project = loadedProject
            company = loadedCompany

            // Load line items and client
            lineItems = try await service.getProposalLineItems(estimateId: loadedEstimate.id)

            if let clientId = loadedProject.clientId {
                client = try await service.getProposalClient(clientId: clientId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func generateProposal(estimateId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            proposal = try await service.generateFromEstimate(estimateId: estimateId)
            if let proposal {
                await loadProposal(id: proposal.id)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func sendProposal() async {
        guard let proposalId = proposal?.id else { return }
        isSending = true
        errorMessage = nil
        do {
            proposal = try await service.sendProposal(id: proposalId)
            successMessage = "Proposal sent successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    func shareProposal() -> URL? {
        shareURL
    }
}
