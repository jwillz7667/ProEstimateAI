import Foundation
import UIKit

/// Drives the proposal preview sheet: loads the latest proposal, sends it to
/// the client, and exposes the shareable approval link. Sending a proposal is
/// the hand-off step of the get-paid loop (estimate → proposal → invoice).
@MainActor
@Observable
final class ProposalPreviewViewModel {
    // MARK: - State

    var proposal: Proposal

    var isLoading = false
    var isSending = false
    private(set) var isSavingDocument = false
    var errorMessage: String?
    var didCopyShareLink = false
    private(set) var reviewedEstimate: Estimate?
    private(set) var reviewedLineItems: [EstimateLineItem] = []
    private(set) var reviewNeedsRefresh = true
    private(set) var failureRevision = 0
    private(set) var lastError: (any Error)?

    // MARK: - Dependencies

    private let service: ProposalServiceProtocol
    private let estimateService: any EstimateServiceProtocol

    // MARK: - Init

    init(proposal: Proposal, reviewedEstimate: Estimate? = nil,
         service: ProposalServiceProtocol = LiveProposalService(),
         estimateService: any EstimateServiceProtocol = LiveEstimateService()) {
        self.proposal = proposal
        self.service = service
        self.reviewedEstimate = reviewedEstimate
        self.estimateService = estimateService
    }

    // MARK: - Derived

    var shareURL: URL? { proposal.shareURL }
    var canSend: Bool {
        proposal.canSend && !isLoading && !isSending && !isSavingDocument
            && (proposal.status != .draft || (!reviewNeedsRefresh && !reviewedLineItems.isEmpty && proposal.draftReviewToken != nil))
    }

    // MARK: - Loading

    func load() async {
        guard !isLoading, !isSending, !isSavingDocument else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let refreshed = try await service.getProposal(id: proposal.id)
            guard refreshed.id == proposal.id, refreshed.companyId == proposal.companyId else { return }
            proposal = refreshed
            async let document = estimateService.getEstimate(id: proposal.estimateId)
            async let items = estimateService.getLineItems(estimateId: proposal.estimateId)
            let (estimate, lineItems) = try await (document, items)
            try Task.checkCancellation()
            guard estimate.id == proposal.estimateId, estimate.companyId == proposal.companyId,
                  lineItems.allSatisfy({ $0.estimateId == estimate.id }) else {
                reviewNeedsRefresh = true
                errorMessage = "The saved estimate couldn't be matched to this proposal. Refresh before sending."
                return
            }
            reviewedEstimate = estimate
            reviewedLineItems = lineItems.sorted { $0.sortOrder < $1.sortOrder }
            reviewNeedsRefresh = false
            errorMessage = nil
        } catch {
            if !Task.isCancelled {
                reviewNeedsRefresh = true
                errorMessage = "The proposal review couldn't be refreshed. \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Actions

    func saveDocument(_ form: ProposalDocumentForm, currentCompanyId: String?, canEdit: Bool) async throws {
        guard proposal.permitsChanges(currentCompanyId: currentCompanyId, canEdit: canEdit) else {
            throw ProposalDocumentError.permissionDenied
        }
        guard proposal.isEditableDraft, !isSending, !isLoading, !isSavingDocument else {
            throw ProposalDocumentError.readOnly
        }
        isSavingDocument = true
        defer { isSavingDocument = false }
        let saved = try await service.updateProposal(id: proposal.id, body: form.request)
        guard saved.id == proposal.id, saved.companyId == proposal.companyId, saved.isEditableDraft else {
            reviewNeedsRefresh = true
            throw ProposalDocumentError.invalidResponse
        }
        proposal = saved
        if let refreshed = try? await service.getProposal(id: proposal.id), refreshed.id == proposal.id, refreshed.companyId == proposal.companyId {
            proposal = refreshed
        } else { reviewNeedsRefresh = true }
        AppEventBus.shared.noteProjectChange()
    }

    func send(currentCompanyId: String?, canEdit: Bool) async {
        guard proposal.permitsChanges(currentCompanyId: currentCompanyId, canEdit: canEdit), canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            proposal = try await service.sendProposal(
                id: proposal.id, clientMessage: nil,
                expectedEstimateUpdatedAt: proposal.status == .draft ? reviewedEstimate?.updatedAt : nil,
                draftReviewToken: proposal.status == .draft ? proposal.draftReviewToken : nil
            )
            AppEventBus.shared.noteProjectChange()
        } catch {
            lastError = error
            failureRevision += 1
            reviewNeedsRefresh = true
            errorMessage = error.localizedDescription
        }
    }

    func copyShareLink() {
        guard let shareURL else { return }
        UIPasteboard.general.string = shareURL.absoluteString
        didCopyShareLink = true
    }
}
