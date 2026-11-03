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

    var draft = EstimateCreationDraft() { didSet { queueDraftSave() } }
    var selectedClient: Client? { didSet { queueDraftSave() } }
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
    private(set) var hasRecoverableDraft = false
    var canResumeRecoveredDraft: Bool { pendingCheckpoint != nil }
    private(set) var recoveredDraftNotice: String?
    private(set) var draftSaveError: String?
    private(set) var restoreNeedsConfirmation = false
    private(set) var isDraftSavedOnDevice = false
    private var companyId: String?
    private var workspaceRevision = 0
    private let service: any EstimateCreationServing
    private let draftStore: (any EstimateDraftPersisting)?
    private var draftScope: EstimateDraftScope?
    private var writerSessionId: UUID?
    private var checkpointPhase = EstimateDraftCheckpoint.Phase.draft
    private var templateRequestId = UUID().uuidString
    private var frozenTemplateDraft: EstimateCreationDraft?
    private var pendingCheckpoint: EstimateDraftCheckpoint?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var applyingCheckpoint = false
    @ObservationIgnored private var finishedDraft = false

    init(service: any EstimateCreationServing, draftStore: (any EstimateDraftPersisting)? = nil) {
        self.service = service
        self.draftStore = draftStore
    }

    var inputsLocked: Bool { isCreating || createdProject != nil || recovery == .checkProjects }
    var isTemplateReplayPending: Bool { frozenTemplateDraft != nil }
    var canCreate: Bool {
        !isCreating && !isRecovering && recovery == .none && createdEstimate == nil && !hasRecoverableDraft
            && (draftStore == nil || writerSessionId != nil)
    }

    func loadClients(companyId: String) async {
        if self.companyId != companyId {
            if self.companyId != nil { resetWorkspaceMemory() }
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

    /// Offer restoration without overwriting any text typed while loading.
    /// Existing saved work is retained until the user chooses resume or discard.
    func restoreDraft(userId: String, companyId: String) async {
        guard let draftStore, self.companyId == companyId, !isCreating, !Task.isCancelled else { return }
        let scope = EstimateDraftScope(userId: userId, companyId: companyId)
        guard scope != draftScope else { return }
        if let previous = draftScope, previous.userId != userId { resetWorkspaceMemory() }
        saveTask?.cancel()
        draftScope = scope
        finishedDraft = false
        do {
            let sessionId = try await draftStore.openSession(scope: scope)
            guard draftScope == scope, !Task.isCancelled else { return }
            writerSessionId = sessionId
            let saved = try await draftStore.load(scope: scope)
            guard draftScope == scope, !Task.isCancelled else { return }
            pendingCheckpoint = saved
            hasRecoverableDraft = saved != nil
            recoveredDraftNotice = saved.map { "Saved draft: \($0.draft.trimmedTitle.isEmpty ? "Untitled estimate" : $0.draft.trimmedTitle)" }
            draftSaveError = nil
        } catch {
            guard draftScope == scope, !Task.isCancelled else { return }
            hasRecoverableDraft = true
            recoveredDraftNotice = "The saved draft needs attention."
            draftSaveError = "The saved draft couldn't be read. Your server projects are still available. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func resumeRecoveredDraft(replacingCurrentInputs: Bool = false) -> Bool {
        guard let saved = pendingCheckpoint, saved.scope == draftScope, !isCreating else { return false }
        let hasInput = draft != EstimateCreationDraft() || selectedClient != nil
        if hasInput && !replacingCurrentInputs {
            restoreNeedsConfirmation = true
            return false
        }
        applyingCheckpoint = true
        defer { applyingCheckpoint = false }
        draft = saved.draft
        selectedClient = clients.first { $0.id == saved.selectedClientId }
        createdProject = saved.project
        createdEstimate = saved.estimate
        checkpointPhase = saved.phase
        templateRequestId = saved.templateRequestId
        frozenTemplateDraft = saved.phase == .estimateWritePending && saved.draft.method == .template ? saved.draft : nil
        switch saved.phase {
        case .draft, .projectSaved, .estimateSaved: recovery = .none
        case .projectWritePending: recovery = .checkProjects
        case .estimateWritePending: recovery = draft.method == .template ? .none : .checkEstimates
        }
        errorMessage = recovery == .none ? nil : "A previous save wasn't confirmed. Check the saved work before creating another copy."
        pendingCheckpoint = nil
        hasRecoverableDraft = false
        restoreNeedsConfirmation = false
        recoveredDraftNotice = "Recovered your saved draft."
        isDraftSavedOnDevice = true
        return true
    }

    /// This discards only the local recovery copy; confirmed server projects
    /// and estimates remain available in Projects.
    func startNewDraft() async {
        guard !isCreating else { return }
        saveTask?.cancel()
        if let scope = draftScope, let session = writerSessionId, let draftStore {
            do { try await draftStore.remove(scope: scope, sessionId: session) }
            catch { draftSaveError = "The local draft couldn't be removed. \(error.localizedDescription)"; return }
        }
        applyingCheckpoint = true
        draft = EstimateCreationDraft()
        selectedClient = nil
        createdProject = nil
        createdEstimate = nil
        recoveredEstimates = []
        checkpointPhase = .draft
        templateRequestId = UUID().uuidString
        frozenTemplateDraft = nil
        recovery = .none
        errorMessage = nil
        lastError = nil
        pendingCheckpoint = nil
        hasRecoverableDraft = false
        restoreNeedsConfirmation = false
        recoveredDraftNotice = nil
        draftSaveError = nil
        isDraftSavedOnDevice = false
        finishedDraft = false
        applyingCheckpoint = false
    }

    func saveDraftNow() async {
        saveTask?.cancel()
        guard !finishedDraft, !hasRecoverableDraft, !applyingCheckpoint,
              draft != EstimateCreationDraft() || selectedClient != nil || createdProject != nil else { return }
        do { try await persistCheckpoint(checkpointPhase) }
        catch { draftSaveError = "Your latest changes couldn't be saved on this device. \(error.localizedDescription)" }
    }

    func finishDraft() async {
        saveTask?.cancel()
        finishedDraft = true
        guard let draftStore, let scope = draftScope, let session = writerSessionId else { return }
        do { try await draftStore.remove(scope: scope, sessionId: session) }
        catch { draftSaveError = "The recovery copy couldn't be cleared. The saved estimate is safe on the server." }
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
        let input = frozenTemplateDraft ?? draft
        if let validation = input.validationMessage { errorMessage = validation; return false }
        if let selectedClient, selectedClient.companyId != companyId {
            errorMessage = "Choose a client from your current company."
            return false
        }
        let revision = workspaceRevision
        let clientId = selectedClient?.id
        isCreating = true
        errorMessage = nil
        lastError = nil
        defer { isCreating = false }
        do {
            if createdProject == nil {
                try await persistCheckpoint(.projectWritePending)
                let project = try await service.createProject(request: input.projectRequest(clientId: clientId, language: language))
                guard revision == workspaceRevision, project.companyId == companyId else {
                    recovery = .checkProjects
                    errorMessage = "The saved project couldn't be matched to this company. Check Projects before trying again."
                    return false
                }
                createdProject = project
                try await persistCheckpoint(.projectSaved)
            }
            guard let project = createdProject, project.companyId == companyId else { return false }
            try Task.checkCancellation()
            try await persistCheckpoint(.estimateWritePending)
            let estimate: Estimate
            if input.method == .template, let templateId = input.templateId {
                estimate = try await service.createEstimateFromTemplate(projectId: project.id, title: input.trimmedTitle,
                    templateId: templateId, requestId: templateRequestId)
            } else {
                estimate = try await service.createEstimate(projectId: project.id, title: input.trimmedTitle, method: input.method)
            }
            guard revision == workspaceRevision, estimate.projectId == project.id, estimate.companyId == companyId else {
                recovery = .checkEstimates
                errorMessage = "The estimate couldn't be matched to this project. Check its saved estimates before creating another."
                return false
            }
            createdEstimate = estimate
            // The result is already confirmed. A failed local journal update
            // must not hide the successfully created server estimate.
            do { try await persistCheckpoint(.estimateSaved) }
            catch { draftSaveError = "The estimate is saved on the server, but its local recovery copy couldn't be updated." }
            frozenTemplateDraft = nil
            return true
        } catch {
            lastError = error
            let uncertain = (error as? any EstimateCreationFailureClassifying)?.creationWriteIsUnconfirmed ?? true
            if uncertain, input.method == .template, createdProject != nil {
                frozenTemplateDraft = input
                recovery = .none
                errorMessage = "The template estimate couldn't be confirmed. Retry safely to retrieve the same estimate; the request ID is preserved."
            } else if uncertain {
                recovery = createdProject == nil ? .checkProjects : .checkEstimates
                errorMessage = createdProject == nil
                    ? "We couldn't confirm whether the project was saved. Check Projects before creating another."
                    : "Your project is saved. We couldn't confirm the estimate yet; check its saved estimates before trying again."
            } else {
                frozenTemplateDraft = nil
                checkpointPhase = createdProject == nil ? .draft : .projectSaved
                try? await persistCheckpoint(checkpointPhase)
                errorMessage = createdProject == nil
                    ? error.localizedDescription
                    : "Your project is saved. \(error.localizedDescription) You can retry this step without creating another project."
            }
            return false
        }
    }

    private func queueDraftSave() {
        guard draftStore != nil, draftScope != nil, !applyingCheckpoint, !finishedDraft, !hasRecoverableDraft else { return }
        saveTask?.cancel()
        isDraftSavedOnDevice = false
        saveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            self?.saveTask = nil
            await self?.saveDraftNow()
        }
    }

    private func resetWorkspaceMemory() {
        saveTask?.cancel()
        applyingCheckpoint = true
        draft = EstimateCreationDraft()
        selectedClient = nil
        createdProject = nil
        createdEstimate = nil
        recoveredEstimates = []
        recovery = .none
        checkpointPhase = .draft
        templateRequestId = UUID().uuidString
        frozenTemplateDraft = nil
        pendingCheckpoint = nil
        hasRecoverableDraft = false
        recoveredDraftNotice = nil
        draftSaveError = nil
        errorMessage = nil
        lastError = nil
        draftScope = nil
        writerSessionId = nil
        finishedDraft = false
        isDraftSavedOnDevice = false
        applyingCheckpoint = false
    }

    private func persistCheckpoint(_ phase: EstimateDraftCheckpoint.Phase) async throws {
        saveTask?.cancel()
        checkpointPhase = phase
        guard let draftStore, let scope = draftScope, let session = writerSessionId else { return }
        guard scope.companyId == companyId, !finishedDraft else { throw EstimateDraftCheckpointFailure() }
        let checkpoint = EstimateDraftCheckpoint(scope: scope, draft: frozenTemplateDraft ?? draft, selectedClientId: selectedClient?.id,
            project: createdProject, estimate: createdEstimate, phase: phase,
            templateRequestId: templateRequestId, savedAt: Date())
        do {
            try await draftStore.save(checkpoint, sessionId: session)
            draftSaveError = nil
            isDraftSavedOnDevice = true
        } catch {
            throw EstimateDraftCheckpointFailure()
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
        checkpointPhase = .estimateSaved
        recovery = .none
        errorMessage = nil
        Task { await saveDraftNow() }
        return true
    }
}

private struct EstimateDraftCheckpointFailure: LocalizedError, EstimateCreationFailureClassifying {
    var creationWriteIsUnconfirmed: Bool { false }
    nonisolated var errorDescription: String? { "The draft couldn't be secured on this device. Check device storage and try again." }
}
