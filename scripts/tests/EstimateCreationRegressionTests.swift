import Foundation

@main
@MainActor
struct EstimateCreationRegressionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw Failure(description: message) }
    }

    static func main() async throws {
        try validation()
        try await manualFlow()
        try await retainedProjectRetry()
        try await uncertainProject()
        try await uncertainEstimate()
        try await tenantIsolation()
        try await duplicateTap()
        print("PASS: \(checks) direct estimate creation checks (scope validation, client ownership, manual/AI choice, retained IDs, ambiguous writes and duplicate taps).")
    }

    static func validation() throws {
        var draft = EstimateCreationDraft()
        try expect(draft.validationMessage != nil, "Empty names cannot create backing projects")
        draft.title = "  Hallway painting \n"
        try expect(draft.validationMessage == nil, "Manual quotes require no AI scope")
        try expect(draft.trimmedTitle == "Hallway painting", "Trimmed names must become saved titles")
        draft.method = .ai
        try expect(draft.validationMessage != nil, "AI estimates require useful scope")
        draft.scope = "Prepare walls and apply two coats of washable paint."
        try expect(draft.validationMessage == nil, "A useful AI scope must be accepted")
        draft.title = String(repeating: "😀", count: 128)
        try expect(draft.validationMessage != nil, "API UTF16 title limits apply to emoji")
        draft.title = String(repeating: "x", count: 255)
        try expect(draft.validationMessage == nil, "The exact name boundary remains valid")
        draft.scope = String(repeating: "x", count: 5001)
        try expect(draft.validationMessage != nil, "Oversize scope must not reach the server")
        draft.scope = " \n "
        draft.method = .manual
        let request = draft.projectRequest(clientId: "client-1", language: "es")
        try expect(request.clientId == "client-1", "Client selection must be in the initial project write")
        try expect(request.description == nil, "Blank optional scope should stay empty")
        try expect(request.language == "es", "Document language must be retained")
        try expect(request.aiPreviewEnabled == false, "Direct estimating must never silently generate an image")
        try expect(request.squareFootage == nil && request.qualityTier == nil, "Quick estimates must not fabricate measurements or tiers")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        try expect(json["client_id"] as? String == "client-1", "Client ownership uses the canonical wire key")
        try expect(json["ai_preview_enabled"] as? Bool == false, "No-preview intent must be explicit on the wire")
    }

    private static func configured(_ service: FakeCreationService) async -> EstimateCreationViewModel {
        let model = EstimateCreationViewModel(service: service)
        await model.loadClients(companyId: Project.sample.companyId)
        model.draft.title = "Hallway painting"
        return model
    }

    static func manualFlow() async throws {
        let service = FakeCreationService()
        let model = await configured(service)
        model.selectClient(Client.sample)
        let completed = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(completed, "Manual creation must open the saved estimate")
        try expect(service.projectCalls == 1 && service.estimateCalls == 1, "One action creates one project and one estimate")
        try expect(service.request?.clientId == Client.sample.id, "Selected client must be linked before editing")
        try expect(service.method == .manual, "Manual path must not consume AI")
        try expect(model.createdProject?.id == Project.sample.id && model.createdEstimate?.id == Estimate.sample.id, "Confirmed server IDs must be retained")
        try expect(!model.canCreate && model.inputsLocked, "Successful work cannot be resubmitted")
        let repeated = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(!repeated && service.projectCalls == 1, "Repeated completion taps must not create duplicates")
    }

    static func retainedProjectRetry() async throws {
        let service = FakeCreationService()
        service.estimateError = CreationFailure.rejected
        let model = await configured(service)
        let failed = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(!failed && model.createdProject != nil, "Rejected estimates must keep a confirmed project")
        try expect(model.recovery == .none && model.canCreate, "A confirmed rejection can resume safely")
        service.estimateError = nil
        let saved = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(saved && service.projectCalls == 1 && service.estimateCalls == 2, "Retry must resume estimate creation, not create a second project")
    }

    static func uncertainProject() async throws {
        let service = FakeCreationService()
        service.projectError = CreationFailure.uncertain
        let model = await configured(service)
        _ = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(model.recovery == .checkProjects, "Unconfirmed project writes require saved-project inspection")
        try expect(!model.canCreate && model.inputsLocked, "Unconfirmed projects must not be blindly retried or renamed")
        _ = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(service.projectCalls == 1 && service.estimateCalls == 0, "No duplicate project POST follows an ambiguous response")
    }

    static func uncertainEstimate() async throws {
        let service = FakeCreationService()
        service.estimateError = CreationFailure.uncertain
        let model = await configured(service)
        _ = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(model.recovery == .checkEstimates && !model.canCreate, "Unconfirmed estimate writes require reconciliation")
        _ = await model.create(companyId: Project.sample.companyId, language: "en")
        try expect(service.estimateCalls == 1, "An ambiguous AI request must not consume a second allowance")
        await model.checkSavedEstimates()
        try expect(model.recoveredEstimates.isEmpty && !model.canCreate, "An immediate empty read cannot prove a slow POST failed")
        service.estimates = [Estimate.sample]
        await model.checkSavedEstimates()
        try expect(model.recoveredEstimates.count == 1, "Reconciliation must expose the saved document")
        try expect(model.chooseRecoveredEstimate(Estimate.sample), "An explicitly selected saved estimate can be opened")
        try expect(model.createdEstimate?.id == Estimate.sample.id && model.recovery == .none, "Recovery must reuse the original estimate")
        try expect(service.projectCalls == 1 && service.estimateCalls == 1, "Recovery is read-only")
    }

    static func tenantIsolation() async throws {
        let service = FakeCreationService()
        let model = await configured(service)
        let changed = await model.create(companyId: "another-company", language: "en")
        try expect(!changed && service.projectCalls == 0, "Stale company forms cannot create under another workspace")
        await model.loadClients(companyId: "another-company")
        try expect(model.clients.isEmpty, "Client lists must reject another tenant's response")
        model.selectClient(Client.sample)
        try expect(model.selectedClient == nil, "A stale client cannot be selected in another company")
        _ = await model.create(companyId: "another-company", language: "en")
        try expect(model.createdProject == nil && model.recovery == .checkProjects, "A mismatched create response must not publish another company's project")
        try expect(service.estimateCalls == 0, "Tenant mismatches cannot progress into estimate creation")
    }

    static func duplicateTap() async throws {
        let service = FakeCreationService()
        service.suspend = true
        let model = await configured(service)
        async let first = model.create(companyId: Project.sample.companyId, language: "en")
        while service.projectCalls == 0 { await Task.yield() }
        let second = await model.create(companyId: Project.sample.companyId, language: "en")
        let result = await first
        try expect(result && !second, "Only the first in-flight submission can complete")
        try expect(service.projectCalls == 1 && service.estimateCalls == 1, "Double taps must remain one creation pipeline")
    }
}

private enum CreationFailure: LocalizedError, EstimateCreationFailureClassifying {
    case rejected, uncertain
    var creationWriteIsUnconfirmed: Bool { self == .uncertain }
    nonisolated var errorDescription: String? { "Test server response" }
}

private final class FakeCreationService: EstimateCreationServing, @unchecked Sendable {
    var projectCalls = 0
    var estimateCalls = 0
    var projectError: CreationFailure?
    var estimateError: CreationFailure?
    var estimates: [Estimate] = []
    var request: ProjectCreationRequest?
    var method: EstimateCreationMethod?
    var suspend = false

    func listClients() async throws -> [Client] { [Client.sample] }
    func createProject(request: ProjectCreationRequest) async throws -> Project {
        projectCalls += 1
        self.request = request
        if suspend { try await Task.sleep(for: .milliseconds(30)) }
        if let projectError { throw projectError }
        return Project.sample
    }
    func createEstimate(projectId: String, title: String, method: EstimateCreationMethod) async throws -> Estimate {
        estimateCalls += 1
        self.method = method
        if let estimateError { throw estimateError }
        return Estimate.sample
    }
    func listEstimates(projectId: String) async throws -> [Estimate] { estimates }
}
