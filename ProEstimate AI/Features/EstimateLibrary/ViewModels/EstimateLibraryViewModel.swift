import Foundation
import Observation

@MainActor @Observable
final class EstimateLibraryViewModel {
    private(set) var templates: [EstimateTemplate] = []
    private(set) var items: [SavedEstimateLibraryItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var nextCursor: String?
    private var query = ""
    private var scope = ""
    private var revision = 0
    private var seenCursors: Set<String> = []
    private let service: any EstimateLibraryServing
    enum Mode: Sendable, Equatable { case templates, items }

    init(service: any EstimateLibraryServing) { self.service = service }

    func load(mode: Mode, scope: String, query: String, more: Bool = false) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !more {
            revision += 1
            if self.scope != scope || self.query != query { templates = []; items = [] }
            self.scope = scope; self.query = query; nextCursor = nil; seenCursors = []
        } else if isLoading || nextCursor == nil { return }
        let current = revision
        let cursor = more ? nextCursor : nil
        isLoading = true; errorMessage = nil
        defer { if revision == current { isLoading = false } }
        do {
            if mode == .templates {
                let page = try await service.templates(query: query, cursor: cursor)
                try Task.checkCancellation()
                guard current == revision else { return }
                try acceptCursor(page.nextCursor)
                templates = Self.unique((more ? templates : []) + page.items)
            } else {
                let page = try await service.items(query: query, cursor: cursor)
                try Task.checkCancellation()
                guard current == revision else { return }
                try acceptCursor(page.nextCursor)
                items = Self.unique((more ? items : []) + page.items)
            }
        } catch {
            guard current == revision, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func acceptCursor(_ cursor: String?) throws {
        if let cursor, !seenCursors.insert(cursor).inserted {
            nextCursor = nil
            throw EstimateEditError.validation("The library returned a repeated page. Refresh the list.")
        }
        nextCursor = cursor
    }
    private static func unique<T: Identifiable>(_ values: [T]) -> [T] {
        var ids: Set<T.ID> = []
        return values.filter { ids.insert($0.id).inserted }
    }
}

/// A mutation retains its UUID and exact input until a confirmed response.
/// Retrying after a lost response replays the same server transaction.
@MainActor @Observable
final class EstimateLibraryMutationModel {
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var pending = false
    private var requestId = UUID()
    private let service: any EstimateLibraryServing
    private var templateRequest: SaveEstimateTemplateRequest?
    private var itemRequest: SaveEstimateLibraryItemRequest?
    private var applyRequest: ApplyEstimateLibraryItemRequest?
    private var applyItemId: String?

    init(service: any EstimateLibraryServing) { self.service = service }

    func saveTemplate(estimateId: String, name: String, description: String) async -> EstimateTemplate? {
        guard !isWorking else { return nil }
        if templateRequest == nil {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.utf16.count <= 200, description.utf16.count <= 2000 else {
                errorMessage = "Use a template name of 1–200 characters and a description up to 2,000 characters."; return nil
            }
            templateRequest = .init(requestId: requestId, estimateId: estimateId, name: name, description: description.isEmpty ? nil : description)
        }
        isWorking = true; pending = true; errorMessage = nil
        defer { isWorking = false }
        do { let result = try await service.saveTemplate(templateRequest!); confirmed(); return result }
        catch { failed(error, message: "Couldn't confirm the saved template. Retry uses the same request."); return nil }
    }

    func saveItem(form: EstimateLineItemForm, itemId: String?, itemType: String?, locale: Locale = .current) async -> SavedEstimateLibraryItem? {
        guard !isWorking else { return nil }
        if itemRequest == nil {
            do { itemRequest = try .init(requestId: requestId, form: form, itemType: itemType, locale: locale) }
            catch { errorMessage = error.localizedDescription; return nil }
        }
        isWorking = true; pending = true; errorMessage = nil
        defer { isWorking = false }
        do { let result = try await service.saveItem(itemRequest!, itemId: itemId); confirmed(); return result }
        catch { failed(error, message: "Couldn't confirm the saved item. Retry uses the same pricing and request."); return nil }
    }

    func applyItem(id: String, estimateId: String) async -> Bool {
        guard !isWorking, applyItemId == nil || applyItemId == id else { return false }
        if applyRequest == nil { applyRequest = .init(requestId: requestId, estimateId: estimateId); applyItemId = id }
        isWorking = true; pending = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await service.applyItem(id: id, request: applyRequest!)
            guard result.estimateId == estimateId else { throw EstimateEditError.invalidResponse }
            confirmed(); return true
        } catch { failed(error, message: "Couldn't confirm the added item. Retry this item to check the same request."); return false }
    }

    func duplicate(estimate: Estimate) async -> Estimate? {
        guard !isWorking else { return nil }
        isWorking = true; pending = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await service.duplicateEstimate(id: estimate.id, request: .init(requestId: requestId))
            guard result.companyId == estimate.companyId, result.projectId == estimate.projectId, result.id != estimate.id, result.isEditable else { throw EstimateEditError.invalidResponse }
            confirmed(); return result
        } catch { failed(error, message: "Couldn't confirm the duplicate. Retry checks the same draft."); return nil }
    }

    private func confirmed() {
        pending = false; requestId = UUID(); templateRequest = nil; itemRequest = nil
        applyRequest = nil; applyItemId = nil
    }

    private func failed(_ error: Error, message: String) {
        if (error as? any EstimateLibraryFailureClassifying)?.libraryWriteWasRejected == true {
            confirmed(); errorMessage = error.localizedDescription
        } else { errorMessage = "\(message) \(error.localizedDescription)" }
    }
}
