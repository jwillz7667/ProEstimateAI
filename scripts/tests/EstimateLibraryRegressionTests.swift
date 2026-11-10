import Foundation

@main @MainActor
struct EstimateLibraryRegressionTests {
    enum Failure: Error { case check(String) }
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1; if !value() { throw Failure.check(message) }
    }
    static func main() async throws {
        try pricingRoundTrips()
        try await pagingAndSearch()
        try await failedMutationsKeepTheirOriginalRequest()
        try await duplicateRetryAndNewIntent()
        try await applyingCannotSwitchTargetsWhileUncertain()
        try await definitiveRejectionAllowsCorrection()
        try await workspaceResultsStayPrivate()
        print("PASS: \(checks) estimate library checks (pricing, pagination, tenant state, idempotent retry and new intent).")
    }

    static func savedItem(_ id: String) -> SavedEstimateLibraryItem {
        .init(id: id, category: .materials, name: "Drywall", description: nil, quantity: 2, unit: "sheets", unitCost: 10,
              markupPercent: 10, taxRate: Decimal(string: "0.0825")!, itemType: "per_unit", createdAt: Date(), updatedAt: Date())
    }
    static func template(_ id: String) -> EstimateTemplate {
        .init(id: id, name: "Cabinets", description: nil, projectType: .kitchen, itemCount: 2, totalAmount: 49.2, createdAt: Date(), updatedAt: Date())
    }
    static func line(estimateId: String) -> EstimateLineItem {
        .init(id: "new-line", estimateId: estimateId, parentLineItemId: nil, sourceMaterialSuggestionId: nil,
              category: .materials, itemType: "per_unit", name: "Drywall", description: nil, quantity: 2,
              unit: "sheets", unitCost: 10, markupPercent: 10, taxRate: 8.25, lineTotal: 22, sortOrder: 0)
    }
    static func copyEstimate() throws -> Estimate {
        let data = try JSONEncoder().encode(Estimate.sample)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["id"] = "new-draft"
        return try JSONDecoder().decode(Estimate.self, from: JSONSerialization.data(withJSONObject: json))
    }
    static func pricingRoundTrips() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        let item = savedItem("item")
        var form = item.editForm(locale: locale)
        try expect(form.taxPercent == "8.25", "Saved tax fraction must become a readable percentage")
        let id = UUID()
        let request = try SaveEstimateLibraryItemRequest(requestId: id, form: form, locale: locale)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        try expect(json["fields"] == nil && json["sort_order"] == nil && json["company_id"] == nil, "Library saves must flatten editable fields and omit ownership/order")
        try expect((json["tax_rate"] as? NSNumber)?.decimalValue == Decimal(string: "0.0825"), "Library save must send a fractional tax")
        try expect((json["request_id"] as? String)?.lowercased() == id.uuidString.lowercased(), "A write must include its stable request UUID")
        form.markupPercent = "1000"
        do { _ = try SaveEstimateLibraryItemRequest(requestId: id, form: form, locale: locale); throw Failure.check("Markup overflow accepted") }
        catch is EstimateEditError { try expect(true, "Catalog must match its decimal markup range") }
        form.markupPercent = "10"; form.quantity = "0.001"
        do { _ = try SaveEstimateLibraryItemRequest(requestId: id, form: form, locale: locale); throw Failure.check("Quantity rounds to zero") }
        catch is EstimateEditError { try expect(true, "Tiny quantities must fail before a zero-valued stored quantity") }
    }

    static func pagingAndSearch() async throws {
        let service = LibraryTestService()
        await service.setItemPages([
            .init(items: [savedItem("a"), savedItem("a")], nextCursor: "page-1"),
            .init(items: [savedItem("a"), savedItem("b")], nextCursor: "page-2"),
            .init(items: [savedItem("c")], nextCursor: "page-2"),
            .init(items: [], nextCursor: nil)
        ])
        let model = EstimateLibraryViewModel(service: service)
        await model.load(mode: .items, scope: "user:company", query: " drywall ")
        try expect(model.items.map(\.id) == ["a"] && model.nextCursor == "page-1", "First page must deduplicate identities")
        await model.load(mode: .items, scope: "user:company", query: "drywall", more: true)
        try expect(model.items.map(\.id) == ["a", "b"], "More pages must append without duplicating saved rows")
        await model.load(mode: .items, scope: "user:company", query: "drywall", more: true)
        try expect(model.errorMessage != nil && model.nextCursor == nil && !model.isLoading, "Repeated cursor must fail explicitly and stop pagination")
        await model.load(mode: .items, scope: "user:company", query: "valve")
        try expect(model.items.isEmpty && model.errorMessage == nil, "A changed search must not retain old matches")
        let calls = await service.itemQueries
        try expect(calls.map(\.0) == ["drywall", "drywall", "drywall", "valve"], "Search input must be normalized and sent to the server")
    }

    static func failedMutationsKeepTheirOriginalRequest() async throws {
        let service = LibraryTestService()
        await service.configureTemplate(result: template("saved"), failureCount: 1)
        let model = EstimateLibraryMutationModel(service: service)
        let unconfirmed = await model.saveTemplate(estimateId: "estimate", name: "Original name", description: "Scope")
        try expect(unconfirmed == nil, "Lost save response must remain unconfirmed")
        try expect(model.pending && !model.isWorking, "Uncertain writes must keep the input locked and support retry")
        let result = await model.saveTemplate(estimateId: "estimate", name: "Changed name", description: "Changed scope")
        let requests = await service.templateWrites
        try expect(result?.id == "saved" && requests.count == 2, "Retry must recover the saved result")
        try expect(requests[0].requestId == requests[1].requestId && requests[1].name == "Original name" && requests[1].description == "Scope", "Retry must retain exact original UUID and payload")
        try expect(!model.pending && model.errorMessage == nil, "A confirmed result must clear uncertainty")
    }

    static func duplicateRetryAndNewIntent() async throws {
        let service = LibraryTestService()
        await service.configureDuplicate(result: try copyEstimate(), failureCount: 1)
        let model = EstimateLibraryMutationModel(service: service)
        _ = await model.duplicate(estimate: .sample)
        _ = await model.duplicate(estimate: .sample)
        _ = await model.duplicate(estimate: .sample)
        let ids = await service.duplicateIds
        try expect(ids.count == 3 && ids[0] == ids[1], "An uncertain duplicate must retry with the same idempotency key")
        try expect(ids[2] != ids[1], "A confirmed duplicate followed by a deliberate new copy needs a new key")
    }

    static func applyingCannotSwitchTargetsWhileUncertain() async throws {
        let service = LibraryTestService()
        await service.configureApply(result: line(estimateId: "estimate"), failureCount: 1)
        let model = EstimateLibraryMutationModel(service: service)
        _ = await model.applyItem(id: "a", estimateId: "estimate")
        let switched = await model.applyItem(id: "b", estimateId: "estimate")
        try expect(!switched, "A different saved item cannot replace an uncertain add")
        let retried = await model.applyItem(id: "a", estimateId: "estimate")
        try expect(retried, "The original add should be safely recoverable")
        let requests = await service.applyWrites
        try expect(requests.count == 2 && requests[0].1.requestId == requests[1].1.requestId, "Apply retry must not create a second request")
    }

    static func definitiveRejectionAllowsCorrection() async throws {
        let service = LibraryTestService()
        await service.configureTemplate(result: template("saved"), failureCount: 1, rejected: true)
        let model = EstimateLibraryMutationModel(service: service)
        _ = await model.saveTemplate(estimateId: "estimate", name: "First", description: "")
        try expect(!model.pending && model.errorMessage != nil, "A server rejection must unlock correctable fields")
        _ = await model.saveTemplate(estimateId: "estimate", name: "Corrected", description: "")
        let writes = await service.templateWrites
        try expect(writes[0].requestId != writes[1].requestId && writes[1].name == "Corrected", "A corrected rejected input needs a new key")
    }

    static func workspaceResultsStayPrivate() async throws {
        let service = LibraryTestService(holdTemplates: true)
        let model = EstimateLibraryViewModel(service: service)
        let old = Task { await model.load(mode: .templates, scope: "company-a", query: "") }
        try await service.waitForTemplateRequests(1)
        let current = Task { await model.load(mode: .templates, scope: "company-b", query: "") }
        try await service.waitForTemplateRequests(2)
        await service.finishTemplate(0, .init(items: [template("private-a")], nextCursor: nil))
        await old.value
        try expect(model.templates.isEmpty && model.isLoading, "Stale company data must neither publish nor stop the current spinner")
        await service.finishTemplate(1, .init(items: [template("private-b")], nextCursor: nil))
        await current.value
        try expect(model.templates.map(\.id) == ["private-b"], "Only current workspace data can publish")
    }
}

struct LibraryTestError: Error, EstimateLibraryFailureClassifying { var libraryWriteWasRejected: Bool }
actor LibraryTestService: EstimateLibraryServing {
    private var itemPages: [EstimateLibraryPage<SavedEstimateLibraryItem>] = []
    private(set) var itemQueries: [(String, String?)] = []
    private(set) var templateWrites: [SaveEstimateTemplateRequest] = []
    private(set) var duplicateIds: [UUID] = []
    private(set) var applyWrites: [(String, ApplyEstimateLibraryItemRequest)] = []
    private var templateResult: EstimateTemplate?
    private var duplicateResult: Estimate?
    private var applyResult: EstimateLineItem?
    private var failures = 0
    private var rejected = false
    private let holdTemplates: Bool
    private var templateCount = 0
    private var continuations: [Int: CheckedContinuation<EstimateLibraryPage<EstimateTemplate>, Never>] = [:]
    init(holdTemplates: Bool = false) { self.holdTemplates = holdTemplates }
    func setItemPages(_ pages: [EstimateLibraryPage<SavedEstimateLibraryItem>]) { itemPages = pages }
    func configureTemplate(result: EstimateTemplate, failureCount: Int, rejected: Bool = false) { templateResult = result; failures = failureCount; self.rejected = rejected }
    func configureDuplicate(result: Estimate, failureCount: Int) { duplicateResult = result; failures = failureCount }
    func configureApply(result: EstimateLineItem, failureCount: Int) { applyResult = result; failures = failureCount }
    func items(query: String, cursor: String?) async throws -> EstimateLibraryPage<SavedEstimateLibraryItem> { itemQueries.append((query, cursor)); return itemPages.removeFirst() }
    func templates(query: String, cursor: String?) async throws -> EstimateLibraryPage<EstimateTemplate> {
        guard holdTemplates else { return .init(items: [], nextCursor: nil) }
        let id = templateCount; templateCount += 1
        return await withCheckedContinuation { continuations[id] = $0 }
    }
    func saveTemplate(_ request: SaveEstimateTemplateRequest) async throws -> EstimateTemplate { templateWrites.append(request); try failIfNeeded(); return templateResult! }
    func duplicateEstimate(id: String, request: DuplicateEstimateRequest) async throws -> Estimate { duplicateIds.append(request.requestId); try failIfNeeded(); return duplicateResult! }
    func applyItem(id: String, request: ApplyEstimateLibraryItemRequest) async throws -> EstimateLineItem { applyWrites.append((id, request)); try failIfNeeded(); return applyResult! }
    func saveItem(_ request: SaveEstimateLibraryItemRequest, itemId: String?) async throws -> SavedEstimateLibraryItem { throw CancellationError() }
    func removeItem(id: String) async throws {}
    func removeTemplate(id: String) async throws {}
    private func failIfNeeded() throws { if failures > 0 { failures -= 1; throw LibraryTestError(libraryWriteWasRejected: rejected) } }
    func finishTemplate(_ id: Int, _ page: EstimateLibraryPage<EstimateTemplate>) { continuations.removeValue(forKey: id)?.resume(returning: page) }
    func waitForTemplateRequests(_ count: Int) async throws {
        for _ in 0 ..< 1000 { if templateCount >= count { return }; try await Task.sleep(for: .milliseconds(1)) }
        throw EstimateLibraryRegressionTests.Failure.check("Timed out waiting for template request")
    }
}
