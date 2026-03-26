import Foundation
import Observation
import SwiftUI

@Observable
final class EstimateEditorViewModel {
    // MARK: - Dependencies

    private let service: EstimateServiceProtocol

    // MARK: - State

    var estimate: Estimate?
    var materialItems: [LineItemDraft] = []
    var laborItems: [LineItemDraft] = []
    var otherItems: [LineItemDraft] = []
    var discountAmount: Decimal = 0
    var notes: String = ""
    var isLoading: Bool = false
    var isSaving: Bool = false
    var hasUnsavedChanges: Bool = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Section Collapse State

    var isMaterialsSectionExpanded: Bool = true
    var isLaborSectionExpanded: Bool = true
    var isOtherSectionExpanded: Bool = true

    // MARK: - Sheet State

    var editingLineItem: LineItemDraft?
    var editingCategory: EstimateLineItem.Category?
    var isLineItemSheetPresented: Bool = false

    // MARK: - Computed Totals (all Decimal arithmetic)

    var subtotalMaterials: Decimal {
        materialItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    var subtotalLabor: Decimal {
        laborItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    var subtotalOther: Decimal {
        otherItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    var subtotal: Decimal {
        subtotalMaterials + subtotalLabor + subtotalOther
    }

    var taxAmount: Decimal {
        let materialsTax = materialItems.reduce(Decimal.zero) { $0 + $1.taxAmount }
        let laborTax = laborItems.reduce(Decimal.zero) { $0 + $1.taxAmount }
        let otherTax = otherItems.reduce(Decimal.zero) { $0 + $1.taxAmount }
        return materialsTax + laborTax + otherTax
    }

    var grandTotal: Decimal {
        let preTaxTotal = materialItems.reduce(Decimal.zero) { $0 + $1.baseCost + $1.markupAmount }
            + laborItems.reduce(Decimal.zero) { $0 + $1.baseCost + $1.markupAmount }
            + otherItems.reduce(Decimal.zero) { $0 + $1.baseCost + $1.markupAmount }
        return preTaxTotal + taxAmount - discountAmount
    }

    var totalItemCount: Int {
        materialItems.count + laborItems.count + otherItems.count
    }

    var versionDisplay: String {
        guard let estimate else { return "v1" }
        return "v\(estimate.version)"
    }

    // MARK: - Init

    init(service: EstimateServiceProtocol = LiveEstimateService()) {
        self.service = service
    }

    // MARK: - Load

    func loadEstimate(id: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedEstimate = try await service.getEstimate(id: id)
            let lineItems = try await service.getLineItems(estimateId: id)

            estimate = loadedEstimate
            discountAmount = loadedEstimate.discountAmount
            notes = loadedEstimate.notes ?? ""

            // Sort line items into category buckets
            materialItems = lineItems
                .filter { $0.category == .materials }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { LineItemDraft(from: $0) }

            laborItems = lineItems
                .filter { $0.category == .labor }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { LineItemDraft(from: $0) }

            otherItems = lineItems
                .filter { $0.category == .other }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { LineItemDraft(from: $0) }

            hasUnsavedChanges = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Line Item CRUD

    func addLineItem(category: EstimateLineItem.Category) {
        var draft = LineItemDraft()
        draft.estimateId = estimate?.id ?? ""
        draft.category = category
        draft.taxRate = category == .labor ? 0 : 8.25 // Labor typically not taxed

        editingLineItem = draft
        editingCategory = category
        isLineItemSheetPresented = true
    }

    func editLineItem(_ item: LineItemDraft) {
        editingLineItem = item
        editingCategory = item.category
        isLineItemSheetPresented = true
    }

    func saveEditingLineItem(_ draft: LineItemDraft) {
        let category = draft.category

        switch category {
        case .materials:
            if let index = materialItems.firstIndex(where: { $0.id == draft.id }) {
                materialItems[index] = draft
            } else {
                var newDraft = draft
                newDraft.sortOrder = materialItems.count
                materialItems.append(newDraft)
            }
        case .labor:
            if let index = laborItems.firstIndex(where: { $0.id == draft.id }) {
                laborItems[index] = draft
            } else {
                var newDraft = draft
                newDraft.sortOrder = laborItems.count
                laborItems.append(newDraft)
            }
        case .other:
            if let index = otherItems.firstIndex(where: { $0.id == draft.id }) {
                otherItems[index] = draft
            } else {
                var newDraft = draft
                newDraft.sortOrder = otherItems.count
                otherItems.append(newDraft)
            }
        }

        hasUnsavedChanges = true
        isLineItemSheetPresented = false
        editingLineItem = nil
        editingCategory = nil
    }

    func deleteLineItem(id: String) {
        materialItems.removeAll { $0.id == id }
        laborItems.removeAll { $0.id == id }
        otherItems.removeAll { $0.id == id }
        reindexSortOrders()
        hasUnsavedChanges = true
    }

    func duplicateLineItem(id: String) {
        if let item = materialItems.first(where: { $0.id == id }) {
            var copy = item
            copy.id = UUID().uuidString
            copy.name = "\(item.name) (Copy)"
            copy.sortOrder = materialItems.count
            materialItems.append(copy)
        } else if let item = laborItems.first(where: { $0.id == id }) {
            var copy = item
            copy.id = UUID().uuidString
            copy.name = "\(item.name) (Copy)"
            copy.sortOrder = laborItems.count
            laborItems.append(copy)
        } else if let item = otherItems.first(where: { $0.id == id }) {
            var copy = item
            copy.id = UUID().uuidString
            copy.name = "\(item.name) (Copy)"
            copy.sortOrder = otherItems.count
            otherItems.append(copy)
        }
        hasUnsavedChanges = true
    }

    func moveLineItem(from source: IndexSet, to destination: Int, category: EstimateLineItem.Category) {
        switch category {
        case .materials:
            materialItems.move(fromOffsets: source, toOffset: destination)
            reindexSortOrders(for: .materials)
        case .labor:
            laborItems.move(fromOffsets: source, toOffset: destination)
            reindexSortOrders(for: .labor)
        case .other:
            otherItems.move(fromOffsets: source, toOffset: destination)
            reindexSortOrders(for: .other)
        }
        hasUnsavedChanges = true
    }

    // MARK: - Save

    func save() async {
        guard let estimate else { return }
        isSaving = true
        errorMessage = nil
        do {
            let allItems = (materialItems + laborItems + otherItems).map { $0.toLineItem() }

            let updatedEstimate = Estimate(
                id: estimate.id,
                projectId: estimate.projectId,
                companyId: estimate.companyId,
                estimateNumber: estimate.estimateNumber,
                version: estimate.version,
                status: estimate.status,
                subtotalMaterials: subtotalMaterials,
                subtotalLabor: subtotalLabor,
                subtotalOther: subtotalOther,
                taxAmount: taxAmount,
                discountAmount: discountAmount,
                totalAmount: grandTotal,
                notes: notes.isEmpty ? nil : notes,
                validUntil: estimate.validUntil,
                createdAt: estimate.createdAt,
                updatedAt: Date()
            )

            self.estimate = try await service.updateEstimate(updatedEstimate)
            _ = try await service.saveLineItems(allItems, estimateId: estimate.id)
            hasUnsavedChanges = false
            successMessage = "Estimate saved successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: - PDF Generation

    /// Renders the current estimate data to a PDF and returns a temporary file URL.
    func generatePDF() -> URL? {
        guard let estimate else { return nil }

        let allItems = (materialItems + laborItems + otherItems)
        let lineItemTuples: [(name: String, qty: Decimal, unit: String, unitCost: Decimal, total: Decimal)] =
            allItems.map { item in
                (name: item.name, qty: item.quantity, unit: item.unit.rawValue, unitCost: item.unitCost, total: item.lineTotal)
            }

        return PDFGenerator.generateEstimatePDF(
            companyName: "ProEstimate AI",
            estimateNumber: estimate.estimateNumber,
            date: estimate.createdAt,
            status: estimate.status.rawValue.capitalized,
            lineItems: lineItemTuples,
            subtotalMaterials: subtotalMaterials,
            subtotalLabor: subtotalLabor,
            subtotalOther: subtotalOther,
            taxAmount: taxAmount,
            discountAmount: discountAmount,
            totalAmount: grandTotal,
            notes: notes.isEmpty ? nil : notes
        )
    }

    // MARK: - Compute

    func computeLineTotal(for item: LineItemDraft) -> Decimal {
        item.lineTotal
    }

    // MARK: - Private Helpers

    private func reindexSortOrders() {
        reindexSortOrders(for: .materials)
        reindexSortOrders(for: .labor)
        reindexSortOrders(for: .other)
    }

    private func reindexSortOrders(for category: EstimateLineItem.Category) {
        switch category {
        case .materials:
            for index in materialItems.indices {
                materialItems[index].sortOrder = index
            }
        case .labor:
            for index in laborItems.indices {
                laborItems[index].sortOrder = index
            }
        case .other:
            for index in otherItems.indices {
                otherItems[index].sortOrder = index
            }
        }
    }
}
