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
    var errorMessage: String?
    var didCopyShareLink = false

    // MARK: - Dependencies

    private let service: ProposalServiceProtocol

    // MARK: - Init

    init(proposal: Proposal, service: ProposalServiceProtocol = LiveProposalService()) {
        self.proposal = proposal
        self.service = service
    }

    // MARK: - Derived

    var shareURL: URL? { proposal.shareURL }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let refreshed = try? await service.getProposal(id: proposal.id) {
            proposal = refreshed
        }
    }

    // MARK: - Actions

    func send() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            proposal = try await service.sendProposal(id: proposal.id, clientMessage: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyShareLink() {
        guard let shareURL else { return }
        UIPasteboard.general.string = shareURL.absoluteString
        didCopyShareLink = true
    }
}
