import Foundation

@main
@MainActor
struct EstimateEditorRegressionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0
    static let us = Locale(identifier: "en_US")

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw Failure(description: message) }
    }

    static func main() async throws {
        try validationAndSerialization()
        try taxPercentRoundTrip()
        try await savedServerTotals()
        try await readOnlyLifecycle()
        try await ambiguousWriteReconciliation()
        try await confirmedWriteWithFailedRefresh()
        try await partialReadDoesNotPublish()
        try await doubleTapIsSingleWrite()
        print("PASS: \(checks) estimate editor checks (validation, tax scaling, canonical totals, lifecycle, ambiguous writes and refresh recovery).")
    }

    static func form() -> EstimateLineItemForm {
        var value = EstimateLineItemForm()
        value.name = "  Cabinet install  "
        value.category = .labor
        value.quantity = "2.5"
        value.unit = "worker-hour"
        value.unitCost = "85.50"
        value.markupPercent = "15"
        value.taxPercent = "8.25"
        return value
    }

    static func validationAndSerialization() throws {
        let request = try form().validatedRequest(locale: us)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        try expect(object["name"] as? String == "Cabinet install", "Names must trim surrounding whitespace")
        try expect(object["description"] is NSNull, "Clearing a description must explicitly encode null")
        try expect((object["tax_rate"] as? NSNumber)?.decimalValue == Decimal(string: "0.0825"), "UI 8.25 percent must encode wire 0.0825")
        try expect((object["markup_percent"] as? NSNumber)?.intValue == 15, "Markup remains a percent on the wire")
        try expect(object["line_total"] == nil && object["estimate_id"] == nil && object["company_id"] == nil, "Editor requests must not send calculated totals or ownership fields")
        try expect(object["unit"] as? String == "worker-hour", "Custom units must not collapse to each")

        let invalid: [(WritableKeyPath<EstimateLineItemForm, String>, String)] = [
            (\.name, " \n "), (\.name, String(repeating: "x", count: 501)),
            (\.name, String(repeating: "😀", count: 251)),
            (\.details, String(repeating: "x", count: 5001)),
            (\.unit, ""), (\.unit, String(repeating: "x", count: 51)),
            (\.quantity, "0"), (\.quantity, "-1"), (\.quantity, "2 hours"),
            (\.unitCost, "-1"), (\.unitCost, "NaN"),
            (\.markupPercent, "1000.01"), (\.taxPercent, "100.01"),
            (\.taxPercent, "Infinity"), (\.taxPercent, "8.25%")
        ]
        for (key, text) in invalid {
            var value = form()
            value[keyPath: key] = text
            do {
                _ = try value.validatedRequest(locale: us)
                throw Failure(description: "Invalid field was accepted: \(key)")
            } catch is EstimateEditError {
                checks += 1
            }
        }
        var boundaries = form()
        boundaries.name = String(repeating: "x", count: 500)
        boundaries.details = String(repeating: "x", count: 5000)
        boundaries.unit = String(repeating: "x", count: 50)
        boundaries.unitCost = "0"
        boundaries.markupPercent = "1000"
        boundaries.taxPercent = "100"
        let valid = try boundaries.validatedRequest(locale: us)
        try expect(valid.taxRate == 1 && valid.unitCost == 0 && valid.markupPercent == 1000, "Exact API boundaries must remain valid")
        var localized = form()
        localized.quantity = "1,5"
        localized.taxPercent = "8,25"
        let german = try localized.validatedRequest(locale: Locale(identifier: "de_DE"))
        try expect(german.quantity == Decimal(string: "1.5") && german.taxRate == Decimal(string: "0.0825"), "Localized decimals must retain value and tax scaling")
    }

    static func taxPercentRoundTrip() throws {
        let encoded = try JSONEncoder().encode(EstimateLineItem.sample)
        let decoded = try JSONDecoder().decode(EstimateLineItem.self, from: encoded)
        try expect(decoded.taxRate == Decimal(string: "8.25"), "Canonical wire fraction must decode to UI percent")
        let edited = try EstimateLineItemForm(item: decoded, locale: us).validatedRequest(locale: us)
        try expect(edited.taxRate == Decimal(string: "0.0825"), "Opening and saving an existing item must not scale tax twice")
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy["tax_rate"] = 8.25
        let legacyDecoded = try JSONDecoder().decode(EstimateLineItem.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(legacyDecoded.taxRate == Decimal(string: "8.25"), "Legacy percent rows must retain the existing decoder compatibility")
    }

    static func savedServerTotals() async throws {
        let service = FakeEstimateEditingService()
        let model = EstimateEditorViewModel(estimateId: Estimate.sample.id, service: service)
        await model.load()
        try expect(model.canEdit, "A fully loaded draft must be editable without a commerce dependency")
        let saved = await model.save(itemId: nil, form: form(), locale: us)
        try expect(saved && service.adds == 1, "Adding a manual line must make exactly one POST")
        try expect(model.estimate?.totalAmount == 999 && model.lineItems.count == 2, "Displayed totals and rows must come from a fresh server snapshot")
        try expect(service.documentReads == 2 && service.itemReads == 2, "Each mutation must reload both canonical document and items")
        var edit = form()
        edit.taxPercent = "0"
        let updated = await model.save(itemId: EstimateLineItem.sample.id, form: edit, locale: us)
        try expect(updated, "An existing line must be editable")
        try expect(service.updates == 1 && service.lastRequest?.taxRate == 0, "Update must preserve explicit zero tax")
        let removed = await model.remove(itemId: EstimateLineItem.sample.id)
        try expect(removed && service.removes == 1 && !model.lineItems.contains(where: { $0.id == EstimateLineItem.sample.id }), "Removal must reconcile saved items")
    }

    static func readOnlyLifecycle() async throws {
        for status in [Estimate.Status.sent, .approved, .declined, .expired] {
            let service = FakeEstimateEditingService()
            service.document = document(status: status)
            let model = EstimateEditorViewModel(estimateId: service.document.id, service: service)
            await model.load()
            let saved = await model.save(itemId: nil, form: form(), locale: us)
            let removed = await model.remove(itemId: EstimateLineItem.sample.id)
            try expect(!model.canEdit && !saved && !removed && service.adds == 0 && service.removes == 0, "Non-draft \(status) must remain readable without mutation calls")
            try expect(model.lineItems.count == 1 && model.estimate != nil, "Read-only estimates must still show their saved work")
        }
    }

    static func ambiguousWriteReconciliation() async throws {
        let service = FakeEstimateEditingService()
        service.throwAfterAdd = true
        let model = EstimateEditorViewModel(estimateId: service.document.id, service: service)
        await model.load()
        let saved = await model.save(itemId: nil, form: form(), locale: us)
        try expect(!saved && model.requiresRefresh && !model.canEdit && model.errorMessage != nil, "An ambiguous write must retain review state and block retries")
        _ = await model.save(itemId: nil, form: form(), locale: us)
        try expect(service.adds == 1, "A lost response must never trigger a duplicate POST")
        await model.load()
        try expect(model.lineItems.count == 2 && model.canEdit && service.adds == 1, "An explicit read must reconcile accepted writes without repeating them")
    }

    static func confirmedWriteWithFailedRefresh() async throws {
        let service = FakeEstimateEditingService()
        service.failReadsAfterAdd = true
        let model = EstimateEditorViewModel(estimateId: service.document.id, service: service)
        await model.load()
        let oldTotal = model.estimate?.totalAmount
        let saved = await model.save(itemId: nil, form: form(), locale: us)
        try expect(saved && model.requiresRefresh && !model.canEdit, "A confirmed write with failed readback must dismiss the mutation form but require review")
        try expect(model.estimate?.totalAmount == oldTotal && model.errorMessage?.contains("was saved") == true, "Failed refresh must preserve existing totals and explain that the write succeeded")
        service.failReads = false
        await model.load()
        try expect(model.estimate?.totalAmount == 999 && model.canEdit, "Explicit refresh must restore the canonical document")
    }

    static func partialReadDoesNotPublish() async throws {
        let service = FakeEstimateEditingService()
        service.failItems = true
        let model = EstimateEditorViewModel(estimateId: service.document.id, service: service)
        await model.load()
        try expect(model.estimate == nil && model.requiresRefresh && !model.canEdit, "A partial read must not publish an editable document with unknown items")
        service.failItems = false
        service.items = [item(id: "wrong-owner", estimateId: "another-estimate")]
        await model.load()
        try expect(model.estimate == nil && !model.canEdit, "A mismatched document response must be rejected")
    }

    static func doubleTapIsSingleWrite() async throws {
        let service = FakeEstimateEditingService()
        service.delayWrites = true
        let model = EstimateEditorViewModel(estimateId: service.document.id, service: service)
        await model.load()
        let first = Task { await model.save(itemId: nil, form: form(), locale: us) }
        for _ in 0 ..< 1000 {
            if model.isSaving { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let second = await model.save(itemId: nil, form: form(), locale: us)
        _ = await first.value
        try expect(!second && service.adds == 1, "A second tap during a mutation must not send another write")
    }

    static func document(status: Estimate.Status = .draft, total: Decimal = Estimate.sample.totalAmount) -> Estimate {
        let s = Estimate.sample
        return Estimate(id: s.id, projectId: s.projectId, companyId: s.companyId,
                        estimateNumber: s.estimateNumber, version: s.version, status: status,
                        title: s.title, pricingProfileId: nil, createdByUserId: nil,
                        subtotalMaterials: s.subtotalMaterials, subtotalLabor: s.subtotalLabor,
                        subtotalOther: s.subtotalOther, taxAmount: s.taxAmount, discountAmount: s.discountAmount,
                        totalAmount: total, contingencyAmount: nil, assumptions: nil, exclusions: nil,
                        notes: nil, validUntil: nil, createdAt: s.createdAt, updatedAt: s.updatedAt)
    }

    static func item(id: String, estimateId: String = Estimate.sample.id, request: EstimateLineItemEditRequest? = nil) -> EstimateLineItem {
        let s = EstimateLineItem.sample
        return EstimateLineItem(id: id, estimateId: estimateId, parentLineItemId: nil,
                                sourceMaterialSuggestionId: nil, category: request?.category ?? s.category,
                                itemType: nil, name: request?.name ?? s.name, description: request?.description,
                                quantity: request?.quantity ?? s.quantity, unit: request?.unit ?? s.unit,
                                unitCost: request?.unitCost ?? s.unitCost, markupPercent: request?.markupPercent ?? s.markupPercent,
                                taxRate: request.map { $0.taxRate * 100 } ?? s.taxRate,
                                lineTotal: 999, sortOrder: request?.sortOrder ?? s.sortOrder)
    }
}

@MainActor
final class FakeEstimateEditingService: EstimateEditing {
    var document = Estimate.sample
    var items = [EstimateLineItem.sample]
    var lastRequest: EstimateLineItemEditRequest?
    var adds = 0
    var updates = 0
    var removes = 0
    var documentReads = 0
    var itemReads = 0
    var throwAfterAdd = false
    var failReadsAfterAdd = false
    var failReads = false
    var failItems = false
    var delayWrites = false

    func getEstimate(id: String) async throws -> Estimate {
        documentReads += 1
        if failReads { throw URLError(.notConnectedToInternet) }
        return document
    }
    func getLineItems(estimateId: String) async throws -> [EstimateLineItem] {
        itemReads += 1
        if failReads || failItems { throw URLError(.notConnectedToInternet) }
        return items
    }
    func addLineItem(estimateId: String, request: EstimateLineItemEditRequest) async throws {
        adds += 1
        if delayWrites { try await Task.sleep(for: .milliseconds(25)) }
        lastRequest = request
        items.append(EstimateEditorRegressionTests.item(id: "added", request: request))
        document = EstimateEditorRegressionTests.document(total: 999)
        if failReadsAfterAdd { failReads = true }
        if throwAfterAdd { throw URLError(.timedOut) }
    }
    func updateLineItem(id: String, request: EstimateLineItemEditRequest) async throws {
        updates += 1
        lastRequest = request
        items = items.map { $0.id == id ? EstimateEditorRegressionTests.item(id: id, request: request) : $0 }
        document = EstimateEditorRegressionTests.document(total: 777)
    }
    func removeLineItem(id: String) async throws {
        removes += 1
        items.removeAll { $0.id == id }
        document = EstimateEditorRegressionTests.document(total: 333)
    }
}

typealias EstimateEditingService = FakeEstimateEditingService
