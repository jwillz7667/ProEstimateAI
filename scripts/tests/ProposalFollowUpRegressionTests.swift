import Foundation

@MainActor private var checks = 0
@MainActor private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    checks += 1
    if !condition() { throw TestFailure.failed(message) }
}
private enum TestFailure: LocalizedError {
    case failed(String), offline
    nonisolated var errorDescription: String? {
        switch self { case let .failed(message): message; case .offline: "Offline test" }
    }
}

@main @MainActor
struct ProposalFollowUpRegressionTests {
    static func main() async throws {
        try proposalModels()
        try documentForm()
        try await queueRecovery()
        try await settingsConsent()
        try await scopeIsolation()
        print("Proposal and follow-up regressions: \(checks) checks passed")
    }

    static func proposalModels() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(Proposal.sample)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["changes_requested_at", "requested_changes_message", "document_hash", "draft_review_token", "acceptance"] { object.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(Proposal.self, from: JSONSerialization.data(withJSONObject: object))
        try expect(legacy.acceptance == nil && legacy.changesRequestedAt == nil, "Old proposal responses must decode without new fields")
        try expect(!legacy.permitsChanges(currentCompanyId: legacy.companyId, canEdit: false), "View-only users cannot edit, revise or send a proposal")
        try expect(!legacy.permitsChanges(currentCompanyId: "another-company", canEdit: true), "An editable role must not grant write controls for another company")
        try expect(!legacy.permitsChanges(currentCompanyId: nil, canEdit: true), "Missing account context must fail closed")
        try expect(legacy.permitsChanges(currentCompanyId: legacy.companyId, canEdit: true), "An authorized company member can use document write actions")
        try expect(!legacy.canSend, "An older sent document with an unknown recipient must not be emailed to a mutable project client")
        var bound = legacy
        bound.recipientName = "Original customer"
        bound.recipientEmail = "original@example.test"
        bound.recipientClientId = "original-client"
        bound.recipientMatchesCurrent = true
        try expect(bound.canSend, "A sent version can be resent only to its recorded current recipient")
        let boundDecode = try JSONDecoder().decode(Proposal.self, from: encoder.encode(bound))
        try expect(boundDecode.recipientEmail == "original@example.test", "Authenticated recipient details must survive model decoding")
        let comparisonJSON = """
        {"id":"co-1","title":"Extra work","reason":"Customer request","base_estimate_number":"EST-1","base_version":1,"base_document_hash":"aaaa","base_total":100.25,"new_total":150.75,"change_amount":50.5,"subtotal_delta":50.5,"tax_delta":0,"discount_delta":0,"billing_effect":"additional_invoice","base_scope":{"line_items":[{"name":"Old scope","description":null,"quantity":1,"unit":"job","line_total":100.25}],"assumptions":"Existing framing","exclusions":null}}
        """
        bound.changeOrder = try JSONDecoder().decode(ProposalChangeOrder.self, from: Data(comparisonJSON.utf8))
        let comparison = try JSONDecoder().decode(Proposal.self, from: encoder.encode(bound)).changeOrder
        try expect(comparison?.changeAmount == Decimal(string: "50.5"), "Change-order differences retain decimal precision")
        try expect(comparison?.baseScope.lineItems.first?.name == "Old scope", "The frozen previously approved scope must decode for review")
        try expect(comparison?.billingExplanation.contains("not a second bill") == true, "A delta invoice must not look like a second full-contract bill")
        bound.recipientMatchesCurrent = false
        try expect(!bound.canSend && bound.shareURL != nil, "Recipient changes stop email but retain the historical reference link")
        var changed = legacy
        changed.changesRequestedAt = Date()
        changed.requestedChangesMessage = "Use oak"
        try expect(!changed.canSend, "A change request must block resending the old offer")
        try expect(changed.shareURL != nil, "The sent reference link remains available after requested changes")
        changed.acceptance = ProposalAcceptance(signerName: "Jordan", acceptedAt: Date(), documentHash: String(repeating: "a", count: 64), estimateVersion: 2, consentText: "Reviewed", consentVersion: "quote-acceptance-v1", identityAssurance: "self_attested")
        let decoded = try JSONDecoder().decode(Proposal.self, from: encoder.encode(changed))
        try expect(decoded.acceptance?.signerName == "Jordan", "Typed acknowledgement identity must decode")
        try expect(decoded.acceptance?.identityAssurance == "self_attested", "A typed name must not be represented as verified identity")
        let request = SendProposalBody(clientMessage: nil, expectedEstimateUpdatedAt: nil, draftReviewToken: "draft-token")
        let json = try JSONSerialization.jsonObject(with: encoder.encode(request)) as! [String: Any]
        try expect(json["draft_review_token"] as? String == "draft-token", "First-send requests carry the reviewed scope/price token")
    }

    static func documentForm() throws {
        var form = ProposalDocumentForm(proposal: Proposal.sample)
        form.title = "   "
        form.terms = ""
        form.scope = "  New scope\n "
        form.hasExpiration = false
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(form.request)) as! [String: Any]
        try expect(json["title"] is NSNull, "Clearing a title must send null")
        try expect(json["terms_and_conditions"] is NSNull, "Clearing saved terms must send null")
        try expect(json["scope_of_work"] as? String == "New scope", "Scope whitespace is trimmed")
        try expect(json["expires_at"] is NSNull, "Clearing an expiry must send null")
        try expect(json["total_amount"] == nil && json["company_id"] == nil, "Narrative editing cannot replace money or ownership")
        form.title = String(repeating: "😀", count: 251)
        try expect(form.validationMessage() != nil, "Title validation must match the server UTF-16 bound")
        form.title = "Good title"
        form.hasExpiration = true
        form.expiration = Date(timeIntervalSince1970: 1)
        try expect(form.validationMessage() != nil, "Expired draft offers need a new expiry or no expiry")
        form.hasExpiration = false
        try expect(form.validationMessage() == nil, "Optional text-only changes remain valid")
    }

    static func queueRecovery() async throws {
        let service = FakeFollowUps()
        let model = FollowUpHistoryModel(kind: .proposal, entityId: "p-1", service: service)
        await model.load(scope: "company-a")
        try expect(model.canSend, "An eligible document can be followed up explicitly")
        try expect(service.requests.isEmpty, "Loading history must not send or queue email")
        service.queueFails = true
        await model.send()
        try expect(service.requests.count == 1 && model.errorMessage != nil, "An uncertain enqueue shows recovery information")
        service.queueFails = false
        await model.send()
        try expect(service.requests.count == 2, "The user can retry the uncertain request")
        try expect(service.requests[0].requestId == service.requests[1].requestId, "An ambiguous queue response must reuse its request UUID")
        try expect(UUID(uuidString: service.requests[0].requestId) != nil, "Request IDs are valid UUIDs")
        try expect(!model.canSend, "A pending message blocks another follow-up")
        try expect(model.history?.messages.first?.statusTitle == "Queued", "Queued does not imply delivered")
        let accepted = FollowUpRecord(id: "accepted", source: "manual", status: "sent", attempts: 1, createdAt: Date(), acceptedAt: Date(), deliveredAt: nil, errorMessage: nil)
        try expect(accepted.statusTitle == "Accepted by email provider", "Provider acceptance must not be mislabeled delivered")
    }

    static func settingsConsent() async throws {
        let service = FakeFollowUps()
        let model = FollowUpSettingsModel(service: service)
        try expect(!model.enabled, "Automatic reminders start off before loading")
        await model.load(scope: "company-a")
        try expect(!model.enabled && !model.canSave, "Loading defaults is not opt-in")
        model.enabled = true
        try expect(service.updates.isEmpty && model.canSave, "A toggle is a draft until explicit Save")
        service.settingsFail = true
        await model.save()
        try expect(model.requiresRefresh && !model.canSave, "An ambiguous settings write requires a read before another change")
        model.enabled = false
        try expect(!model.canSave, "A stale off draft cannot hide a possibly saved opt-in")
        service.settingsFail = false
        service.settingsValue = FollowUpSettings(enabled: true, quoteDays: 3, invoiceDays: 7, enabledAt: Date(), deliveryAvailable: true, canManage: true)
        await model.load(scope: "company-a")
        try expect(model.enabled && !model.requiresRefresh, "Refresh reconciles the saved consent state")
        model.enabled = false
        await model.save()
        try expect(service.updates.last?.enabled == false && !model.enabled, "Disabling reminders is an explicit saved action")
        await model.load(scope: "company-b")
        try expect(!model.enabled, "Workspace changes do not reuse another company's opt-in draft")
    }

    static func scopeIsolation() async throws {
        let service = FakeFollowUps()
        service.holdHistory = true
        let model = FollowUpHistoryModel(kind: .proposal, entityId: "p-1", service: service)
        let older = Task { await model.load(scope: "old-company") }
        while service.historyContinuation == nil { await Task.yield() }
        service.holdHistory = false
        service.historyValue = service.makeHistory(email: "new@example.test")
        await model.load(scope: "new-company")
        let stale = service.makeHistory(email: "old@example.test")
        service.historyContinuation?.resume(returning: stale)
        service.historyContinuation = nil
        await older.value
        try expect(model.history?.recipientEmail == "new@example.test", "An old company's response must never overwrite new workspace content")
        try expect(!model.isLoading, "Discarded stale responses must not leave loading stuck")
    }
}

enum AppConstants { static let proposalShareBaseURL = URL(string: "https://example.invalid/proposal")! }

private final class FakeFollowUps: FollowUpServing, @unchecked Sendable {
    var requests: [QueueFollowUpRequest] = []
    var updates: [UpdateFollowUpSettings] = []
    var queueFails = false
    var settingsFail = false
    var holdHistory = false
    var historyContinuation: CheckedContinuation<FollowUpHistory, Never>?
    var settingsValue = FollowUpSettings(enabled: false, quoteDays: 3, invoiceDays: 7, enabledAt: nil, deliveryAvailable: true, canManage: true)
    var historyValue = FollowUpHistory(eligible: true, unavailableReason: nil, deliveryAvailable: true, recipientEmail: "client@example.test", suppressed: false, lastContactAt: nil, messages: [])

    func makeHistory(email: String) -> FollowUpHistory { FollowUpHistory(eligible: true, unavailableReason: nil, deliveryAvailable: true, recipientEmail: email, suppressed: false, lastContactAt: nil, messages: []) }
    func history(kind: FollowUpKind, entityId: String) async throws -> FollowUpHistory {
        if holdHistory { return await withCheckedContinuation { historyContinuation = $0 } }
        return historyValue
    }
    func queue(_ request: QueueFollowUpRequest) async throws -> FollowUpRecord {
        requests.append(request)
        if queueFails { throw TestFailure.offline }
        let receipt = FollowUpRecord(id: "queue-1", source: "manual", status: "queued", attempts: 0, createdAt: Date(), acceptedAt: nil, deliveredAt: nil, errorMessage: nil)
        historyValue = FollowUpHistory(eligible: false, unavailableReason: "Pending", deliveryAvailable: true, recipientEmail: "client@example.test", suppressed: false, lastContactAt: nil, messages: [receipt])
        return receipt
    }
    func settings() async throws -> FollowUpSettings { settingsValue }
    func updateSettings(_ request: UpdateFollowUpSettings) async throws -> FollowUpSettings {
        updates.append(request)
        if settingsFail { throw TestFailure.offline }
        settingsValue = FollowUpSettings(enabled: request.enabled, quoteDays: request.quoteDays, invoiceDays: request.invoiceDays, enabledAt: request.enabled ? Date() : nil, deliveryAvailable: true, canManage: true)
        return settingsValue
    }
}
