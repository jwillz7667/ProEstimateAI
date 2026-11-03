import Foundation

@main @MainActor struct ChangeOrderRegressionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws { checks += 1; if !value() { throw Failure(description: message) } }
    static let scope = EstimateDraftScope(userId: "user-1", companyId: Estimate.sample.companyId)
    static func sample(status: String = "draft") -> ChangeOrder {
        let e = Estimate.sample
        return ChangeOrder(id: "change-1", projectId: e.projectId, baseEstimateId: "base-1", estimateId: e.id, proposalId: "proposal-1", rootInvoiceId: "invoice-1", status: status, title: "Add cabinets", reason: "Customer requested storage", comparison: ChangeOrderComparison(id: "change-1", title: "Add cabinets", reason: "Customer requested storage", currencyCode: "USD", baseEstimateNumber: "EST-1", baseVersion: 1, baseDocumentHash: String(repeating: "a", count: 64), baseTotal: 100, newTotal: 125, changeAmount: 25, subtotalDelta: 25, taxDelta: 0, discountDelta: 0, billingEffect: "additional_invoice"), estimate: e, invoices: [], creditNote: nil, createdAt: Date())
    }
    static func main() async throws {
        let request = try CreateChangeOrderRequest.validated(baseEstimateId: "base-1", title: "  Added storage  ", reason: "  Customer request  ")
        try expect(request.title == "Added storage" && request.reason == "Customer request", "Normalize title and reason before freezing a request")
        try expect(UUID(uuidString: request.requestId) != nil, "Create request has a UUID")
        for (title, reason) in [("", "Change"), ("Change", " "), (String(repeating: "a", count: 201), "Change")] {
            do { _ = try CreateChangeOrderRequest.validated(baseEstimateId: "base-1", title: title, reason: reason); throw Failure(description: "Invalid form accepted") } catch is ChangeOrderError { checks += 1 }
        }
        let service = FakeChangeOrders(), journal = FakeChangeOrderJournal()
        let model = ChangeOrderMutationModel(service: service, journal: journal)
        await model.restore(scope: scope, resourceId: "base-1")
        service.fail = true
        await model.create(title: "Original title", reason: "Original scope")
        try expect(model.pending != nil && service.creates.count == 1, "Lost response keeps the exact persisted request")
        let frozen = model.pending!.create!
        try expect(journal.stored?.create == frozen, "Body reaches protected journal before the write")
        await model.create(title: "Different title", reason: "Different scope")
        try expect(service.creates.count == 2 && service.creates[1] == frozen, "New text cannot replace unresolved request identity")
        let restarted = ChangeOrderMutationModel(service: service, journal: journal)
        await restarted.restore(scope: scope, resourceId: "base-1")
        try expect(restarted.pending?.create == frozen, "Restart restores the frozen request")
        service.fail = false
        await restarted.retry()
        try expect(restarted.result?.id == "change-1" && restarted.pending == nil && journal.stored == nil, "Confirmed replay clears journal after showing saved result")
        let applyJournal = FakeChangeOrderJournal(), applyModel = ChangeOrderMutationModel(service: service, journal: applyJournal)
        await applyModel.restore(scope: scope, resourceId: "change-1")
        service.fail = true
        await applyModel.apply()
        let applyRequest = applyModel.pending!.apply!
        service.fail = false
        await applyModel.apply()
        try expect(service.applies.count == 2 && service.applies.allSatisfy { $0 == applyRequest }, "Apply retries preserve UUID and don't double bill")
        try expect(applyModel.result?.status == "applied" && applyModel.pending == nil, "Only matching applied result confirms the financial mutation")
        let foreign = FakeChangeOrderJournal()
        foreign.stored = ChangeOrderPending(scope: EstimateDraftScope(userId: "other", companyId: scope.companyId), resourceId: "base-1", create: frozen, apply: nil)
        let blocked = ChangeOrderMutationModel(service: service, journal: foreign)
        await blocked.restore(scope: scope, resourceId: "base-1")
        try expect(!blocked.isReady && blocked.pending == nil, "Cross-account recovery fails closed")
        var corrupt = ChangeOrderPending(scope: scope, resourceId: "base-1", create: frozen, apply: nil)
        corrupt.schemaVersion = 99
        foreign.stored = corrupt
        await blocked.restore(scope: scope, resourceId: "base-1")
        try expect(!blocked.isReady, "Unsupported recovery versions fail closed")
        let unavailable = FakeChangeOrderJournal(); unavailable.failSave = true
        let offline = ChangeOrderMutationModel(service: service, journal: unavailable)
        await offline.restore(scope: scope, resourceId: "base-1")
        let previous = service.creates.count
        await offline.create(title: "Title", reason: "Scope")
        try expect(service.creates.count == previous && offline.pending == nil, "No POST occurs when the recovery journal cannot save")
        try await realJournal()
        try invoiceCredits()
        print("PASS: \(checks) change order checks (validation, frozen replay, restart, tenant scope, protected journal and credit-aware invoice decoding).")
    }
    static func realJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EstimateDraftStore(directory: directory)
        let journal = ChangeOrderJournal(store: store)
        let pending = ChangeOrderPending(scope: scope, resourceId: "base-1", create: try CreateChangeOrderRequest.validated(baseEstimateId: "base-1", title: "Title", reason: "Reason"), apply: nil)
        try await journal.save(pending)
        let restored = try await journal.load(scope: scope, resourceId: "base-1")
        try expect(restored == pending, "Actual encrypted-device store roundtrips exact request")
        let other = try await journal.load(scope: EstimateDraftScope(userId: "other", companyId: scope.companyId), resourceId: "base-1")
        try expect(other == nil, "Disk journal is isolated by account")
        try await store.purge(userId: scope.userId)
        do { try await journal.save(pending); throw Failure(description: "Revoked session saved") } catch { checks += 1 }
        let fresh = ChangeOrderJournal(store: store)
        let deleted = try await fresh.load(scope: scope, resourceId: "base-1")
        try expect(deleted == nil, "Signout purge prevents stale view from recreating a financial request")
    }
    static func invoiceCredits() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Invoice.sample)) as! [String: Any]
        object["credit_amount"] = 100; object["amount_paid"] = 0; object["amount_due"] = 0; object["status"] = "paid"; object["financial_basis_locked"] = true
        let invoice = try JSONDecoder().decode(Invoice.self, from: JSONSerialization.data(withJSONObject: object))
        try expect(invoice.creditAmount == 100 && invoice.amountPaid == 0 && invoice.statusLabel == "Settled", "Credit settlement is never presented as cash received")
        object["status"] = "draft"
        let frozen = try JSONDecoder().decode(Invoice.self, from: JSONSerialization.data(withJSONObject: object))
        try expect(!frozen.isEditable, "Financial basis of a delta invoice remains locked while draft")
        try expect(Invoice.sample.creditAmount == nil, "Legacy DTOs remain compatible")
    }
}
@MainActor final class FakeChangeOrders: ChangeOrderServing {
    var fail = false
    var creates: [CreateChangeOrderRequest] = []
    var applies: [ApplyChangeOrderRequest] = []
    func list(projectId: String) async throws -> [ChangeOrder] { [] }
    func get(id: String) async throws -> ChangeOrder { ChangeOrderRegressionTests.sample() }
    func create(_ request: CreateChangeOrderRequest) async throws -> ChangeOrder { creates.append(request); if fail { throw URLError(.networkConnectionLost) }; return ChangeOrderRegressionTests.sample() }
    func apply(id: String, request: ApplyChangeOrderRequest) async throws -> ChangeOrder { applies.append(request); if fail { throw URLError(.timedOut) }; return ChangeOrderRegressionTests.sample(status: "applied") }
}
@MainActor final class FakeChangeOrderJournal: ChangeOrderJournaling {
    var stored: ChangeOrderPending?
    var failSave = false
    func load(scope: EstimateDraftScope, resourceId: String) async throws -> ChangeOrderPending? { stored }
    func save(_ pending: ChangeOrderPending) async throws { if failSave { throw CocoaError(.fileWriteOutOfSpace) }; stored = pending }
    func remove(scope: EstimateDraftScope, resourceId: String) async throws { stored = nil }
}
@MainActor struct AppEventBus { static let shared = AppEventBus(); func noteProjectChange() {} }
enum StatusBadge { enum Style { case neutral, info, warning, success, error } }
