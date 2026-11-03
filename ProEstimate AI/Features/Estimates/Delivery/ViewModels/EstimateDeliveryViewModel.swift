import Foundation
import Observation

@MainActor
@Observable
final class EstimateDeliveryViewModel {
    private(set) var project: Project?
    private(set) var client: Client?
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var needsClientRefresh = false
    private(set) var needsProposalReconciliation = false
    private(set) var needsInvoiceReconciliation = false
    private(set) var errorMessage: String?
    private(set) var lastError: (any Error)?
    private let service: any EstimateDeliveryServing
    private var revisionRequestIds: [String: String] = [:]

    init(service: any EstimateDeliveryServing) { self.service = service }

    var hasClient: Bool { client != nil && !needsClientRefresh }

    func load(for estimate: Estimate) async {
        guard !isLoading, !isWorking else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await service.getProject(id: estimate.projectId)
            guard loaded.id == estimate.projectId, loaded.companyId == estimate.companyId else {
                throw EstimateDeliveryError.invalidResponse
            }
            let loadedClient: Client?
            if let clientId = loaded.clientId {
                let value = try await service.getClient(id: clientId)
                guard value.id == clientId, value.companyId == estimate.companyId else { throw EstimateDeliveryError.invalidResponse }
                loadedClient = value
            } else { loadedClient = nil }
            try Task.checkCancellation()
            project = loaded
            client = loadedClient
            needsClientRefresh = false
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            needsClientRefresh = true
            errorMessage = "Client details couldn't be refreshed. Refresh before sending. \(error.localizedDescription)"
        }
    }

    func assign(client: Client, estimate: Estimate) async -> Bool {
        guard !isWorking, !isLoading, client.companyId == estimate.companyId,
              project?.id == estimate.projectId, !needsClientRefresh else { return false }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let updated = try await service.assignClient(projectId: estimate.projectId, clientId: client.id)
            guard updated.id == estimate.projectId, updated.companyId == estimate.companyId, updated.clientId == client.id else {
                throw EstimateDeliveryError.invalidResponse
            }
            project = updated
            self.client = client
            errorMessage = nil
            return true
        } catch {
            lastError = error
            needsClientRefresh = true
            errorMessage = "The client assignment couldn't be confirmed. Refresh and review the saved client before sending."
            return false
        }
    }

    func prepareProposal(estimate: Estimate, hasLineItems: Bool) async -> Proposal? {
        guard !isWorking, !isLoading else { return nil }
        guard hasLineItems else { errorMessage = "Add at least one line item before sending."; return nil }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        var attemptedCreate = false
        do {
            let proposals = try await service.listProposals(projectId: estimate.projectId)
            if let saved = proposals.filter({ $0.estimateId == estimate.id && $0.companyId == estimate.companyId })
                .max(by: { $0.createdAt < $1.createdAt }) {
                needsProposalReconciliation = false
                errorMessage = nil
                return saved
            }
            guard !needsProposalReconciliation else {
                errorMessage = "No saved proposal is visible yet. Check again shortly before creating another."
                return nil
            }
            guard estimate.isEditable else {
                errorMessage = "There is no saved proposal for this estimate. Create a revision to prepare a new proposal."
                return nil
            }
            guard hasClient, project?.id == estimate.projectId, client?.companyId == estimate.companyId else {
                errorMessage = "Choose a client before sending this estimate."
                return nil
            }
            attemptedCreate = true
            let proposal = try await service.createProposal(estimateId: estimate.id)
            guard proposal.estimateId == estimate.id, proposal.projectId == estimate.projectId, proposal.companyId == estimate.companyId else {
                throw EstimateDeliveryError.invalidResponse
            }
            errorMessage = nil
            return proposal
        } catch {
            lastError = error
            if attemptedCreate {
                needsProposalReconciliation = (error as? any EstimateCreationFailureClassifying)?.creationWriteIsUnconfirmed ?? true
            }
            errorMessage = needsProposalReconciliation
                ? "The proposal may have been saved. Check saved proposals before trying again."
                : error.localizedDescription
            return nil
        }
    }

    func revise(estimate: Estimate) async -> Estimate? {
        guard !isWorking, !isLoading, !estimate.isEditable else { return nil }
        let requestId = revisionRequestIds[estimate.id] ?? UUID().uuidString
        revisionRequestIds[estimate.id] = requestId
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let revised = try await service.reviseEstimate(estimateId: estimate.id, requestId: requestId)
            guard revised.id != estimate.id, revised.isEditable, revised.projectId == estimate.projectId,
                  revised.companyId == estimate.companyId else { throw EstimateDeliveryError.invalidResponse }
            errorMessage = nil
            return revised
        } catch {
            lastError = error
            errorMessage = "The revision couldn't be confirmed. Retrying uses the same request and won't create a second revision. \(error.localizedDescription)"
            return nil
        }
    }

    func convertToInvoice(estimate: Estimate) async -> Invoice? {
        guard !isWorking, !isLoading, estimate.status == .approved else { return nil }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        var attemptedCreate = false
        do {
            let invoices = try await service.listInvoices(projectId: estimate.projectId)
            if let saved = invoices.filter({ $0.estimateId == estimate.id && $0.companyId == estimate.companyId && $0.status != .void })
                .max(by: { $0.createdAt < $1.createdAt }) {
                needsInvoiceReconciliation = false
                errorMessage = nil
                return saved
            }
            guard !needsInvoiceReconciliation else {
                errorMessage = "No saved invoice is visible yet. Check again shortly before creating another."
                return nil
            }
            guard hasClient, project?.id == estimate.projectId else {
                errorMessage = "Refresh the saved client before creating an invoice."
                return nil
            }
            attemptedCreate = true
            let invoice = try await service.convertToInvoice(estimateId: estimate.id)
            guard invoice.estimateId == estimate.id, invoice.projectId == estimate.projectId,
                  invoice.companyId == estimate.companyId else { throw EstimateDeliveryError.invalidResponse }
            errorMessage = nil
            return invoice
        } catch {
            lastError = error
            if attemptedCreate {
                needsInvoiceReconciliation = (error as? any EstimateCreationFailureClassifying)?.creationWriteIsUnconfirmed ?? true
            }
            errorMessage = needsInvoiceReconciliation
                ? "The invoice may have been created. Check saved invoices before trying again."
                : error.localizedDescription
            return nil
        }
    }
}

private enum EstimateDeliveryError: LocalizedError {
    case invalidResponse
    nonisolated var errorDescription: String? { "The server response didn't match this estimate." }
}
