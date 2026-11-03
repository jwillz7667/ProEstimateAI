import Foundation

@main
@MainActor
struct EstimateDeliveryRegressionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw Failure(description: message) }
    }

    static func changing<T: Codable>(_ value: T, _ changes: [String: Any]) throws -> T {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        for (key, change) in changes { object[key] = change }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func main() async throws {
        try shareAndVersionSerialization()
        try await clientOwnership()
        try await draftRequiresClient()
        try await proposalReconciliation()
        try await sentProposalReadAccess()
        try await idempotentRevision()
        try await invoiceReconciliation()
        print("PASS: \(checks) estimate delivery checks (client ownership, proposal recovery, sent links, millisecond review guard, stable revision requests and invoice recovery).")
    }

    static func shareAndVersionSerialization() throws {
        let draft = try changing(Proposal.sample, ["status": "draft"])
        try expect(draft.shareURL == nil && draft.canSend, "Draft tokens must stay unshareable until sending captures their document")
        let viewed = try changing(Proposal.sample, ["status": "viewed"])
        try expect(viewed.shareURL != nil && viewed.canSend, "Viewed proposals can be followed up without creating a new proposal")
        let approved = try changing(Proposal.sample, ["status": "approved"])
        try expect(approved.shareURL != nil && !approved.canSend, "Decided proposals stay readable without another approval request")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: "2026-11-03T12:13:14.123Z")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = SendProposalBody(clientMessage: nil, expectedEstimateUpdatedAt: date)
        let object = try JSONSerialization.jsonObject(with: encoder.encode(body)) as! [String: Any]
        try expect(object["expected_estimate_updated_at"] as? String == "2026-11-03T12:13:14.123Z", "Review guard must preserve milliseconds despite the global ISO encoder")
        try expect(object["client_message"] == nil, "Unchanged optional client messages should remain omitted")
        let request = EstimateRevisionRequest(requestId: "d6ee685f-72f0-4fea-8d0a-fb85a92f6487")
        let revision = try JSONSerialization.jsonObject(with: encoder.encode(request)) as! [String: Any]
        try expect(revision["request_id"] as? String == request.requestId, "Revision idempotency uses the canonical request key")
    }

    static func clientOwnership() async throws {
        let service = FakeDeliveryService()
        let model = EstimateDeliveryViewModel(service: service)
        await model.load(for: Estimate.sample)
        try expect(model.hasClient && model.client?.id == Client.sample.id, "Delivery must show the saved client")
        let foreign = try changing(Client.sample, ["company_id": "another-company"])
        let assigned = await model.assign(client: foreign, estimate: Estimate.sample)
        try expect(!assigned && service.assignmentCalls == 0, "Another company's client must never be assigned")
        service.assignmentError = DeliveryFailure.uncertain
        let failed = await model.assign(client: Client.sample, estimate: Estimate.sample)
        try expect(!failed && model.needsClientRefresh, "Uncertain assignment requires a canonical refresh")
        let blocked = await model.assign(client: Client.sample, estimate: Estimate.sample)
        try expect(!blocked && service.assignmentCalls == 1, "Assignment cannot be blindly retried after transport loss")
        await model.load(for: Estimate.sample)
        try expect(model.hasClient && !model.needsClientRefresh, "A read-only refresh can reconcile saved client identity")
    }

    static func draftRequiresClient() async throws {
        let service = FakeDeliveryService()
        service.project = try changing(Project.sample, ["client_id": NSNull()])
        let model = EstimateDeliveryViewModel(service: service)
        await model.load(for: Estimate.sample)
        let missing = await model.prepareProposal(estimate: Estimate.sample, hasLineItems: true)
        try expect(missing == nil && service.createProposalCalls == 0, "A new proposal requires explicit client assignment")
        let empty = await model.prepareProposal(estimate: Estimate.sample, hasLineItems: false)
        try expect(empty == nil && service.createProposalCalls == 0, "Empty estimates cannot be sent from the editor")
    }

    static func proposalReconciliation() async throws {
        let service = FakeDeliveryService()
        let model = EstimateDeliveryViewModel(service: service)
        await model.load(for: Estimate.sample)
        service.proposalError = DeliveryFailure.uncertain
        let first = await model.prepareProposal(estimate: Estimate.sample, hasLineItems: true)
        try expect(first == nil && model.needsProposalReconciliation, "A lost proposal response must block another create")
        _ = await model.prepareProposal(estimate: Estimate.sample, hasLineItems: true)
        try expect(service.createProposalCalls == 1, "A slow response followed by an empty list must not cause duplicate proposals")
        service.proposals = [Proposal.sample]
        let recovered = await model.prepareProposal(estimate: Estimate.sample, hasLineItems: true)
        try expect(recovered?.id == Proposal.sample.id && !model.needsProposalReconciliation, "Saved proposals should be recovered read-only")
        try expect(service.createProposalCalls == 1, "Recovery must reuse the original proposal")
        service.proposals = []
        service.proposalError = DeliveryFailure.rejected
        _ = await model.prepareProposal(estimate: Estimate.sample, hasLineItems: true)
        try expect(!model.needsProposalReconciliation, "Confirmed rejections can be retried after correction")
    }

    static func sentProposalReadAccess() async throws {
        let service = FakeDeliveryService()
        service.project = try changing(Project.sample, ["client_id": NSNull()])
        service.proposals = [Proposal.sample]
        let model = EstimateDeliveryViewModel(service: service)
        await model.load(for: Estimate.sample)
        let sent = try changing(Estimate.sample, ["status": "sent"])
        let saved = await model.prepareProposal(estimate: sent, hasLineItems: true)
        try expect(saved?.id == Proposal.sample.id, "A historic sent proposal remains reachable without creating a new customer link")
        service.proposals = []
        let absent = await model.prepareProposal(estimate: sent, hasLineItems: true)
        try expect(absent == nil && service.createProposalCalls == 0, "A locked estimate with no proposal must use a new revision")
    }

    static func idempotentRevision() async throws {
        let service = FakeDeliveryService()
        let model = EstimateDeliveryViewModel(service: service)
        let sent = try changing(Estimate.sample, ["status": "sent"])
        let draftAttempt = await model.revise(estimate: Estimate.sample)
        try expect(draftAttempt == nil && service.revisionRequests.isEmpty, "Drafts should be edited directly, not revised")
        service.revisionError = DeliveryFailure.uncertain
        _ = await model.revise(estimate: sent)
        service.revisionError = nil
        service.revision = try changing(Estimate.sample, ["id": "e-revision", "version": 2])
        let revised = await model.revise(estimate: sent)
        try expect(revised?.id == "e-revision", "Revision returns a new editable estimate")
        try expect(service.revisionRequests.count == 2 && service.revisionRequests[0] == service.revisionRequests[1], "A lost revision response must reuse the same idempotency key")
        try expect(UUID(uuidString: service.revisionRequests[0]) != nil, "Revision requests use valid UUIDs")
    }

    static func invoiceReconciliation() async throws {
        let service = FakeDeliveryService()
        let model = EstimateDeliveryViewModel(service: service)
        await model.load(for: Estimate.sample)
        let draft = await model.convertToInvoice(estimate: Estimate.sample)
        try expect(draft == nil && service.invoiceCalls == 0, "Only approved work can be invoiced from this action")
        let approved = try changing(Estimate.sample, ["status": "approved"])
        service.invoiceError = DeliveryFailure.uncertain
        _ = await model.convertToInvoice(estimate: approved)
        try expect(model.needsInvoiceReconciliation, "An ambiguous invoice write requires inspection")
        _ = await model.convertToInvoice(estimate: approved)
        try expect(service.invoiceCalls == 1, "Invoice recovery cannot blindly recreate the bill")
        service.invoices = [Invoice.sample]
        let saved = await model.convertToInvoice(estimate: approved)
        try expect(saved?.id == Invoice.sample.id && !model.needsInvoiceReconciliation, "An existing invoice is reused after response loss")
        try expect(service.invoiceCalls == 1, "Opening an invoice must not change the customer's bill")
    }
}

enum AppConstants { static let proposalShareBaseURL = URL(string: "https://example.invalid/proposal")! }
enum StatusBadge { enum Style { case neutral, info, success, warning, error } }

private enum DeliveryFailure: LocalizedError, EstimateCreationFailureClassifying {
    case rejected, uncertain
    var creationWriteIsUnconfirmed: Bool { self == .uncertain }
    nonisolated var errorDescription: String? { "Test delivery failure" }
}

private final class FakeDeliveryService: EstimateDeliveryServing, @unchecked Sendable {
    var project = Project.sample
    var proposals: [Proposal] = []
    var invoices: [Invoice] = []
    var revision = Estimate.sample
    var assignmentError: DeliveryFailure?
    var proposalError: DeliveryFailure?
    var revisionError: DeliveryFailure?
    var invoiceError: DeliveryFailure?
    var assignmentCalls = 0
    var createProposalCalls = 0
    var invoiceCalls = 0
    var revisionRequests: [String] = []

    func getProject(id: String) async throws -> Project { project }
    func getClient(id: String) async throws -> Client { Client.sample }
    func assignClient(projectId: String, clientId: String) async throws -> Project {
        assignmentCalls += 1
        if let assignmentError { throw assignmentError }
        return project
    }
    func listProposals(projectId: String) async throws -> [Proposal] { proposals }
    func createProposal(estimateId: String) async throws -> Proposal {
        createProposalCalls += 1
        if let proposalError { throw proposalError }
        return Proposal.sample
    }
    func reviseEstimate(estimateId: String, requestId: String) async throws -> Estimate {
        revisionRequests.append(requestId)
        if let revisionError { throw revisionError }
        return revision
    }
    func listInvoices(projectId: String) async throws -> [Invoice] { invoices }
    func convertToInvoice(estimateId: String) async throws -> Invoice {
        invoiceCalls += 1
        if let invoiceError { throw invoiceError }
        return Invoice.sample
    }
}
