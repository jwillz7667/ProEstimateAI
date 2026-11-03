import Foundation
import Observation

@MainActor
@Observable
final class EstimateEditorViewModel {
    let estimateId: String
    private(set) var estimate: Estimate?
    private(set) var lineItems: [EstimateLineItem] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var requiresRefresh = true
    private(set) var errorMessage: String?
    private let service: any EstimateEditing

    var canEdit: Bool {
        estimate?.isEditable == true && !isLoading && !isSaving && !requiresRefresh
    }

    init(estimateId: String, service: any EstimateEditing = EstimateEditingService()) {
        self.estimateId = estimateId
        self.service = service
    }

    func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true
        defer { isLoading = false }
        _ = await readSnapshot()
    }

    func newItemForm() -> EstimateLineItemForm {
        var form = EstimateLineItemForm()
        form.sortOrder = (lineItems.map(\.sortOrder).max() ?? -1) + 1
        return form
    }

    /// One mutation per tap. A failed response may follow an accepted write;
    /// disable further edits until explicit reconciliation instead of retrying.
    func save(itemId: String?, form: EstimateLineItemForm, locale: Locale = .current) async -> Bool {
        guard canEdit else { return false }
        let request: EstimateLineItemEditRequest
        do { request = try form.validatedRequest(locale: locale) }
        catch { errorMessage = error.localizedDescription; return false }
        if let itemId, !lineItems.contains(where: { $0.id == itemId }) {
            errorMessage = "This item is no longer in the estimate. Refresh before editing."
            requiresRefresh = true
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let itemId {
                try await service.updateLineItem(id: itemId, request: request)
            } else {
                try await service.addLineItem(estimateId: estimateId, request: request)
            }
            requiresRefresh = true
            if !(await readSnapshot()) {
                errorMessage = "Your item was saved. Refresh the estimate to see its current items and totals."
            }
            return true
        } catch {
            requiresRefresh = true
            errorMessage = "We couldn't confirm the saved changes. Review the estimate before trying again. \(error.localizedDescription)"
            return false
        }
    }

    func remove(itemId: String) async -> Bool {
        guard canEdit, lineItems.contains(where: { $0.id == itemId }) else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await service.removeLineItem(id: itemId)
            requiresRefresh = true
            if !(await readSnapshot()) {
                errorMessage = "The item was removed. Refresh the estimate to see its updated total."
            }
            return true
        } catch {
            requiresRefresh = true
            errorMessage = "We couldn't confirm the removal. Review the estimate before trying again. \(error.localizedDescription)"
            return false
        }
    }

    func saveDocument(form: EstimateDocumentForm, locale: Locale = .current) async -> Bool {
        guard canEdit, let estimate else { return false }
        let request: EstimateDocumentEditRequest
        do { request = try form.validatedRequest(estimate: estimate, locale: locale) }
        catch { errorMessage = error.localizedDescription; return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await service.updateDocument(estimateId: estimateId, request: request)
            requiresRefresh = true
            if !(await readSnapshot()) { errorMessage = "Details were saved. Refresh to review the current document and total." }
            return true
        } catch {
            requiresRefresh = true
            errorMessage = "The saved details couldn't be confirmed. Reload and review them before trying again. \(error.localizedDescription)"
            return false
        }
    }

    private func readSnapshot() async -> Bool {
        do {
            async let document = service.getEstimate(id: estimateId)
            async let items = service.getLineItems(estimateId: estimateId)
            let (loadedEstimate, loadedItems) = try await (document, items)
            try Task.checkCancellation()
            guard loadedEstimate.id == estimateId, loadedItems.allSatisfy({ $0.estimateId == estimateId }) else {
                throw EstimateEditError.invalidResponse
            }
            estimate = loadedEstimate
            lineItems = loadedItems.sorted {
                $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
            }
            requiresRefresh = false
            errorMessage = nil
            return true
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                requiresRefresh = true
                errorMessage = "The estimate couldn't be refreshed. \(error.localizedDescription)"
            }
            return false
        }
    }
}
