import Foundation

@MainActor final class PriceReviewFake: EstimatePriceReviewServing {
    var calls = 0
    var shouldFail = false
    var wrongItem = false
    func review(itemId: String, request: EstimatePriceReviewRequest) async throws -> EstimateLineItem {
        calls += 1
        try await Task.sleep(for: .milliseconds(10))
        if shouldFail { throw NSError(domain: "Fixture", code: 1) }
        var result = EstimateLineItem.sample
        result.priceCheckedAt = Date(timeIntervalSince1970: 100)
        if wrongItem {
            return EstimateLineItem(id: "foreign-item", estimateId: result.estimateId, parentLineItemId: nil,
                sourceMaterialSuggestionId: nil, category: .materials, itemType: nil, name: "Different item", description: nil,
                quantity: 1, unit: "each", unitCost: 1, markupPercent: 0, taxRate: 0, lineTotal: 1, sortOrder: 0)
        }
        return result
    }
}

@main struct EstimatePriceReviewTests {
    @MainActor static func main() async {
        var checks = 0
        func check(_ value: Bool, _ description: String) { checks += 1; if !value { fatalError(description) } }
        var form = EstimatePriceReviewForm()
        check(form.validationMessage != nil, "Missing source is invalid")
        form.sourceLabel = " Supplier quote "
        check(form.validationMessage != nil, "Price confirmation must be explicit")
        form.priceConfirmed = true
        check(form.validationMessage == nil, "A checked source can be recorded")
        for url in ["javascript:alert(1)", "file:///private/receipt", "https://user:secret@example.com", "https://", "ftp://example.com"] {
            form.sourceURL = url; check(form.validationMessage != nil, "Unsafe source URL rejected")
        }
        form.sourceURL = " https://example.com/catalog "
        form.quantityConfirmed = true
        check(form.validationMessage != nil, "Quantity confirmation needs a basis")
        form.quantityBasis = " Counted ten handles on site "
        check(form.validationMessage == nil, "Quantity basis accepted")
        let item = EstimateLineItem.sample
        let request = form.request(for: item)!
        check(request.expected_unit_cost == item.unitCost, "Review binds the exact saved unit cost")
        check(request.expected_quantity == item.quantity, "Review binds the exact quantity")
        check(request.source_label == "Supplier quote", "Source trimmed")
        check(request.source_url == "https://example.com/catalog", "Source link trimmed")
        check(request.quantity_basis == "Counted ten handles on site", "Basis trimmed")
        form.quantityBasis = String(repeating: "x", count: 501)
        check(form.validationMessage != nil, "Oversize basis rejected")
        form.quantityBasis = "Counted on site"
        let fake = PriceReviewFake()
        let model = EstimatePriceReviewModel(item: item, service: fake)
        model.form = form
        async let first = model.save()
        async let second = model.save()
        let results = await [first, second]
        check(fake.calls == 1, "Double tap does not submit two reviews")
        check(results.filter { $0 }.count == 1, "Only one confirmation succeeds")
        fake.shouldFail = true
        check(await model.save() == false, "Unconfirmed save does not dismiss")
        check(model.errorMessage != nil, "Unconfirmed save is explained")
        fake.shouldFail = false; fake.wrongItem = true
        check(await model.save() == false, "Wrong item response is rejected")
        var provenance = item
        check(provenance.priceOriginLabel == "Price source not recorded", "Legacy source is not invented")
        provenance.priceOrigin = "ai_suggested"
        check(provenance.priceOriginLabel == "AI suggested", "AI source remains distinct")
        provenance.priceOrigin = "saved_item"
        check(provenance.priceOriginLabel == "Saved company item", "Saved pricing is identified")
        let encoded = try! JSONEncoder().encode(request)
        let object = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        check(object["price_confirmed"] as? Bool == true, "Wire confirmation is explicit")
        check(object["expected_unit_cost"] as? Double == 75, "Wire price is canonical")
        check(object["markup_percent"] == nil, "Review does not mutate pricing")
        print("PASS: \(checks) estimate price review checks")
    }
}
