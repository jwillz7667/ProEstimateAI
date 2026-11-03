import Foundation

@main
@MainActor
struct EstimateDraftRecoveryTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0
    static let scope = EstimateDraftScope(userId: "user-a", companyId: "c-001")

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw Failure(description: message) }
    }

    static func checkpoint(phase: EstimateDraftCheckpoint.Phase = .draft) -> EstimateDraftCheckpoint {
        var draft = EstimateCreationDraft()
        draft.title = "Protected saved quote"
        draft.scope = "Paint the hallway and repair damaged trim."
        return EstimateDraftCheckpoint(scope: scope, draft: draft, selectedClientId: Client.sample.id,
            project: phase == .draft || phase == .projectWritePending ? nil : Project.sample,
            estimate: phase == .estimateSaved ? Estimate.sample : nil, phase: phase,
            templateRequestId: "0097cba8-a7c7-46c8-b680-5db79ce0a8df", savedAt: Date())
    }

    private static func configured(_ store: any EstimateDraftPersisting, service: RecoveryCreationService = RecoveryCreationService()) async -> EstimateCreationViewModel {
        let model = EstimateCreationViewModel(service: service, draftStore: store)
        await model.loadClients(companyId: scope.companyId)
        await model.restoreDraft(userId: scope.userId, companyId: scope.companyId)
        return model
    }

    static func main() async throws {
        try await explicitRestoreAndDiscard()
        try await crashMarkersPreventReplay()
        try await templateReplayUsesSameRequest()
        try await failedCheckpointPreventsPOST()
        try await realFilesScopingAndPurge()
        print("PASS: \(checks) persistent draft checks (explicit restore, input replacement, account isolation, crash checkpoints, template replay, protected files, corruption and revoked writer sessions).")
    }

    static func explicitRestoreAndDiscard() async throws {
        let store = MemoryDraftStore()
        await store.seed(checkpoint())
        let model = await configured(store)
        try expect(model.hasRecoverableDraft && model.draft.title.isEmpty, "Saved work must be offered, not silently overwrite the current form")
        try expect(!model.canCreate, "The user must decide what to do with existing recovery work")
        model.draft.title = "A new unsaved quote"
        try expect(!model.resumeRecoveredDraft() && model.restoreNeedsConfirmation, "Restoring cannot silently replace newly typed input")
        try expect(model.draft.title == "A new unsaved quote", "Unconfirmed restoration preserves current text")
        try expect(model.resumeRecoveredDraft(replacingCurrentInputs: true), "Explicit replacement can restore the saved draft")
        try expect(model.draft.title == "Protected saved quote" && model.selectedClient?.id == Client.sample.id, "Restoration preserves scope and client identity")
        model.draft.title = "Updated after recovery"
        await model.saveDraftNow()
        let updated = try await store.load(scope: scope)
        try expect(updated?.draft.title == "Updated after recovery", "Explicit flush must persist the latest text")
        await model.startNewDraft()
        let removed = try await store.load(scope: scope)
        try expect(removed == nil && model.draft.title.isEmpty, "Explicit discard clears local recovery without a server mutation")
        try expect(!model.hasRecoverableDraft && model.canCreate, "Discard returns to a fresh usable form")
    }

    static func crashMarkersPreventReplay() async throws {
        let store = MemoryDraftStore()
        await store.seed(checkpoint(phase: .projectWritePending))
        let service = RecoveryCreationService()
        let model = await configured(store, service: service)
        _ = model.resumeRecoveredDraft()
        try expect(model.recovery == .checkProjects && !model.canCreate, "A crash during project creation must require saved-project inspection")
        _ = await model.create(companyId: scope.companyId, language: "en")
        try expect(service.projectCalls == 0 && service.estimateCalls == 0, "Restoration cannot replay an uncertain project POST")
        await store.seed(checkpoint(phase: .estimateWritePending))
        let estimateModel = await configured(store, service: service)
        _ = estimateModel.resumeRecoveredDraft()
        try expect(estimateModel.createdProject?.id == Project.sample.id && estimateModel.recovery == .checkEstimates, "An uncertain estimate retains its confirmed project ID")
        _ = await estimateModel.create(companyId: scope.companyId, language: "en")
        try expect(service.projectCalls == 0 && service.estimateCalls == 0, "Neither AI nor manual estimate POSTs are blindly replayed after a crash")
        await store.seed(checkpoint(phase: .estimateSaved))
        let completeModel = await configured(store)
        _ = completeModel.resumeRecoveredDraft()
        try expect(completeModel.createdEstimate?.id == Estimate.sample.id && !completeModel.canCreate, "A confirmed estimate restores its identity instead of creating another")
        await completeModel.finishDraft()
        let cleared = try await store.load(scope: scope)
        try expect(cleared == nil, "Opening confirmed server work can clear its local recovery copy")
    }

    static func templateReplayUsesSameRequest() async throws {
        let store = MemoryDraftStore()
        let service = RecoveryCreationService()
        let model = await configured(store, service: service)
        model.draft.title = "Template hallway quote"
        model.draft.method = .template
        try expect(model.draft.validationMessage != nil, "Template creation requires an actual saved template")
        model.draft.templateId = "template-a"
        service.templateShouldFail = true
        let first = await model.create(companyId: scope.companyId, language: "en")
        try expect(!first && model.createdProject != nil && model.canCreate, "Template retry can safely reuse its idempotent request")
        try expect(model.isTemplateReplayPending, "Uncertain templates must freeze their exact starting point")
        model.draft.method = .manual
        model.draft.templateId = "another-template"
        model.draft.title = "Changed title"
        _ = await model.create(companyId: scope.companyId, language: "en")
        try expect(service.estimateCalls == 0 && service.templateInputs.allSatisfy({ $0 == "template-a:Template hallway quote" }), "A pending template cannot switch to Manual/AI or change its source/payload")
        let saved = try await store.load(scope: scope)
        try expect(saved?.phase == .estimateWritePending && saved?.project?.id == Project.sample.id, "The pending template request must be journaled with its project")
        let restarted = await configured(store, service: service)
        _ = restarted.resumeRecoveredDraft()
        service.templateShouldFail = false
        let finished = await restarted.create(companyId: scope.companyId, language: "en")
        try expect(finished && service.projectCalls == 1, "Restarting a template operation must reuse the existing project")
        try expect(service.templateRequests.count == 3 && Set(service.templateRequests).count == 1, "Template instantiation retains its exact idempotency key across app restarts")
        let complete = try await store.load(scope: scope)
        try expect(complete?.phase == .estimateSaved && complete?.estimate?.id == Estimate.sample.id, "Confirmed estimate IDs must be journaled before the UI opens")
    }

    static func failedCheckpointPreventsPOST() async throws {
        let store = MemoryDraftStore()
        let service = RecoveryCreationService()
        let model = await configured(store, service: service)
        model.draft.title = "Offline-safe manual quote"
        await store.setFailWrites(true)
        let result = await model.create(companyId: scope.companyId, language: "en")
        try expect(!result && service.projectCalls == 0, "Failure to persist the pre-POST marker must prevent an unrecoverable write")
        try expect(model.recovery == .none, "A local storage rejection is known not to have created a server project")
        await store.setFailWrites(false)
        let success = await model.create(companyId: scope.companyId, language: "en")
        try expect(success && service.projectCalls == 1 && service.estimateCalls == 1, "A corrected storage failure can resume without duplicate server work")
    }

    static func realFilesScopingAndPurge() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("proestimate-draft-tests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EstimateDraftStore(directory: directory)
        let session = try await store.openSession(scope: scope)
        try await store.save(checkpoint(), sessionId: session)
        let loaded = try await store.load(scope: scope)
        try expect(loaded?.draft.title == "Protected saved quote", "Actual atomic files must round-trip their draft")
        let otherUser = EstimateDraftScope(userId: "user-b", companyId: scope.companyId)
        let otherCompany = EstimateDraftScope(userId: scope.userId, companyId: "company-b")
        let userData = try await store.load(scope: otherUser)
        let companyData = try await store.load(scope: otherCompany)
        try expect(userData == nil && companyData == nil, "Accounts and companies cannot inherit each other's cached drafts")
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let files = try FileManager.default.contentsOfDirectory(at: folders[0], includingPropertiesForKeys: nil)
        try expect(!folders[0].lastPathComponent.contains(scope.userId) && !files[0].lastPathComponent.contains(scope.companyId), "Private account identifiers must not appear in file names")
        let attrs = try FileManager.default.attributesOfItem(atPath: files[0].path)
        try expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Draft files must be private to the current OS account")
        try Data("corrupted".utf8).write(to: files[0])
        do { _ = try await store.load(scope: scope); throw Failure(description: "Corrupt recovery files were accepted") }
        catch is Failure { throw Failure(description: "Corrupt recovery files were accepted") }
        catch { checks += 1 }
        let corruptModel = await configured(store)
        try expect(corruptModel.hasRecoverableDraft && !corruptModel.canResumeRecoveredDraft && !corruptModel.canCreate, "Corruption requires an explicit discard before replacing the recovery file")
        await corruptModel.startNewDraft()
        try expect(corruptModel.canCreate, "Explicit discard must recover from corrupt local data")
        try await store.save(checkpoint(), sessionId: session)
        try await store.purge(userId: scope.userId)
        let purged = try await store.load(scope: scope)
        try expect(purged == nil, "Sign-out purge removes the account's recovery copies")
        do { try await store.save(checkpoint(), sessionId: session); throw Failure(description: "Revoked writer recreated private data") }
        catch is Failure { throw Failure(description: "Revoked writer recreated private data") }
        catch { checks += 1 }
        let fresh = try await store.openSession(scope: scope)
        try await store.save(checkpoint(), sessionId: fresh)
        let freshData = try await store.load(scope: scope)
        try expect(freshData != nil, "A new signed-in view can create a new recovery session")
    }
}

private actor MemoryDraftStore: EstimateDraftPersisting {
    private var values: [EstimateDraftScope: EstimateDraftCheckpoint] = [:]
    private var failWrites = false
    func seed(_ checkpoint: EstimateDraftCheckpoint) { values[checkpoint.scope] = checkpoint }
    func setFailWrites(_ value: Bool) { failWrites = value }
    func openSession(scope: EstimateDraftScope) async throws -> UUID { UUID() }
    func load(scope: EstimateDraftScope) async throws -> EstimateDraftCheckpoint? { values[scope] }
    func save(_ checkpoint: EstimateDraftCheckpoint, sessionId: UUID) async throws {
        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        values[checkpoint.scope] = checkpoint
    }
    func remove(scope: EstimateDraftScope, sessionId: UUID) async throws { values[scope] = nil }
}

private enum RecoveryFailure: Error, EstimateCreationFailureClassifying {
    case uncertain
    var creationWriteIsUnconfirmed: Bool { true }
}

private final class RecoveryCreationService: EstimateCreationServing, @unchecked Sendable {
    var projectCalls = 0
    var estimateCalls = 0
    var templateRequests: [String] = []
    var templateInputs: [String] = []
    var templateShouldFail = false
    func listClients() async throws -> [Client] { [Client.sample] }
    func createProject(request: ProjectCreationRequest) async throws -> Project { projectCalls += 1; return Project.sample }
    func createEstimate(projectId: String, title: String, method: EstimateCreationMethod) async throws -> Estimate { estimateCalls += 1; return Estimate.sample }
    func createEstimateFromTemplate(projectId: String, title: String, templateId: String, requestId: String) async throws -> Estimate {
        templateRequests.append(requestId)
        templateInputs.append("\(templateId):\(title)")
        if templateShouldFail { throw RecoveryFailure.uncertain }
        return Estimate.sample
    }
    func listEstimates(projectId: String) async throws -> [Estimate] { [Estimate.sample] }
}
