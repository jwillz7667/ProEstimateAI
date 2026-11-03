import Foundation
import Observation

@MainActor
@Observable
final class EstimateCreationViewModel {
    enum Recovery: Equatable {
        case none
        case checkProjects
        case checkEstimates
    }

    var draft = EstimateCreationDraft()
    var selectedClient: Client?
    private(set) var clients: [Client] = []
    private(set) var isLoadingClients = false
    private(set) var clientsError: String?
    private(set) var isCreating = false
    private(set) var isRecovering = false
    private(set) var createdProject: Project?
    private(set) var createdEstimate: Estimate?
    private(set) var recoveredEstimates: [Estimate] = []
    private(set) var recovery = Recovery.none
    private(set) var errorMessage: String?
    private(set) var lastError: (any Error)?
    private var companyId: String?
    private var workspaceRevision = 0
    private let service: any EstimateCreationServing

    init(service: any EstimateCreationServing) { self.service = service }

    var inputsLocked: Bool { isCreating || createdProject != nil || recovery == .checkProjects }
    var canCreate: Bool { !isCreating && !isRecovering && recovery == .none && createdEstimate == nil }

    func loadClients(companyId: String) async {
        if self.companyId != companyId {
            self.companyId = companyId
            workspaceRevision += 1
            clients = []
            selectedClient = nil
        }
        let revision = workspaceRevision
        isLoadingClients = true
        clientsError = nil
        defer { if revision == workspaceRevision { isLoadingClients = false } }
        do {
            let loaded = try await service.listClients()
            try Task.checkCancellation()
            guard revision == workspaceRevision else { return }
            clients = loaded.filter { $0.companyId == companyId }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            guard revision == workspaceRevision, !Task.isCancelled else { return }
            clientsError = "Clients couldn't be loaded. You can retry or add a new client."
        }
    }

    func selectClient(_ client: Client?) {
        guard !inputsLocked, client == nil || client?.companyId == companyId else { return }
        selectedClient = client
        if let client, !clients.contains(where: { $0.id == client.id }) {
            clients.append(client)
            clients.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Keep every confirmed ID. A rejected estimate can resume on its existing
    /// project; an uncertain POST must be inspected before another is attempted.
    func create(companyId: String, language: String) async -> Bool {
        guard canCreate else { return false }
        guard self.companyId == companyId, !companyId.isEmpty else {
            errorMessage = "Your company changed. Close this estimate and start again."
            return false
        }
        if let validation = draft.validationMessage { errorMessage = validation; return false }
        if let selectedClient, selectedClient.companyId != companyId {
            errorMessage = "Choose a client from your current company."
            return false
        }
        let revision = workspaceRevision
        let input = draft
        let clientId = selectedClient?.id
        isCreating = true
        errorMessage = nil
        lastError = nil
        defer { isCreating = false }
        do {
            if createdProject == nil {
                let project = try await service.createProject(request: input.projectRequest(clientId: clientId, language: language))
                guard revision == workspaceRevision, project.companyId == companyId else {
                    recovery = .checkProjects
                    errorMessage = "The saved project couldn't be matched to this company. Check Projects before trying again."
                    return false
                }
                createdProject = project
            }
            guard let project = createdProject, project.companyId == companyId else { return false }
            try Task.checkCancellation()
            let estimate = try await service.createEstimate(projectId: project.id, title: input.trimmedTitle, method: input.method)
            guard revision == workspaceRevision, estimate.projectId == project.id, estimate.companyId == companyId else {
                recovery = .checkEstimates
                errorMessage = "The estimate couldn't be matched to this project. Check its saved estimates before creating another."
                return false
            }
            createdEstimate = estimate
            return true
        } catch {
            lastError = error
            let uncertain = (error as? any EstimateCreationFailureClassifying)?.creationWriteIsUnconfirmed ?? true
            if uncertain {
                recovery = createdProject == nil ? .checkProjects : .checkEstimates
                errorMessage = createdProject == nil
                    ? "We couldn't confirm whether the project was saved. Check Projects before creating another."
                    : "Your project is saved. We couldn't confirm the estimate yet; check its saved estimates before trying again."
            } else {
                errorMessage = createdProject == nil
                    ? error.localizedDescription
                    : "Your project is saved. \(error.localizedDescription) You can retry this step without creating another project."
            }
            return false
        }
    }

    func checkSavedEstimates() async {
        guard recovery == .checkEstimates, let project = createdProject, !isRecovering, !isCreating else { return }
        isRecovering = true
        defer { isRecovering = false }
        do {
            let values = try await service.listEstimates(projectId: project.id)
            recoveredEstimates = values.filter { $0.projectId == project.id && $0.companyId == project.companyId }
            errorMessage = recoveredEstimates.isEmpty
                ? "No estimate is visible yet. Check again shortly or open the saved project. Don't create a duplicate while the original request may still be finishing."
                : "Choose the saved estimate to review."
        } catch {
            errorMessage = "Saved estimates couldn't be checked. Your project is still available in Projects. \(error.localizedDescription)"
        }
    }

    func chooseRecoveredEstimate(_ estimate: Estimate) -> Bool {
        guard !isRecovering, let project = createdProject,
              recoveredEstimates.contains(where: { $0.id == estimate.id }),
              estimate.projectId == project.id, estimate.companyId == project.companyId else { return false }
        createdEstimate = estimate
        recovery = .none
        errorMessage = nil
        return true
    }
}
