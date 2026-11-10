import Foundation
import Observation

struct EstimatePriceReviewRequest: Encodable, Sendable {
    let expected_name: String
    let expected_unit: String
    let expected_unit_cost: Decimal
    let expected_quantity: Decimal
    let price_confirmed: Bool
    let source_label: String
    let source_url: String?
    let quantity_confirmed: Bool
    let quantity_basis: String?
}

struct EstimatePriceReviewForm: Sendable {
    var sourceLabel = ""
    var sourceURL = ""
    var priceConfirmed = false
    var quantityConfirmed = false
    var quantityBasis = ""

    var validationMessage: String? {
        let source = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty || source.utf16.count > 255 { return "Describe the price source in 1–255 characters." }
        let link = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty {
            guard link.utf16.count <= 2000, let url = URLComponents(string: link),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false, url.user == nil, url.password == nil else {
                return "Use a valid HTTP or HTTPS link without a username or password."
            }
        }
        if !priceConfirmed { return "Confirm that you checked the base price." }
        let basis = quantityBasis.trimmingCharacters(in: .whitespacesAndNewlines)
        if basis.utf16.count > 500 || (quantityConfirmed && basis.isEmpty) { return "Describe how the quantity was checked, using at most 500 characters." }
        return nil
    }

    func request(for item: EstimateLineItem) -> EstimatePriceReviewRequest? {
        guard validationMessage == nil else { return nil }
        let link = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return EstimatePriceReviewRequest(expected_name: item.name, expected_unit: item.unit,
            expected_unit_cost: item.unitCost, expected_quantity: item.quantity,
            price_confirmed: true, source_label: sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            source_url: link.isEmpty ? nil : link, quantity_confirmed: quantityConfirmed,
            quantity_basis: quantityConfirmed ? quantityBasis.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
    }
}

protocol EstimatePriceReviewServing: Sendable {
    func review(itemId: String, request: EstimatePriceReviewRequest) async throws -> EstimateLineItem
}

@MainActor @Observable
final class EstimatePriceReviewModel {
    let item: EstimateLineItem
    var form: EstimatePriceReviewForm
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private let service: any EstimatePriceReviewServing

    init(item: EstimateLineItem, service: any EstimatePriceReviewServing) {
        self.item = item
        self.service = service
        form = EstimatePriceReviewForm(sourceLabel: item.priceSourceLabel ?? "", sourceURL: item.priceSourceUrl ?? "",
                                      quantityBasis: item.quantityBasis ?? "")
    }

    func save() async -> Bool {
        guard !isSaving, let request = form.request(for: item) else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved = try await service.review(itemId: item.id, request: request)
            guard saved.id == item.id, saved.estimateId == item.estimateId else {
                errorMessage = "The saved item could not be matched. Refresh the estimate before continuing."
                return false
            }
            return true
        } catch {
            errorMessage = "The check couldn't be confirmed. Refresh the estimate if the item has changed. \(error.localizedDescription)"
            return false
        }
    }
}
