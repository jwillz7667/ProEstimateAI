import Foundation
import Observation

@MainActor
@Observable
final class JobCostViewModel {
    let projectId: String
    private(set) var entries: [JobCostEntry] = []
    private(set) var summary: JobCostSummary?
    private(set) var pending: JobCostPending?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isWorking = false
    private(set) var journalNeedsAttention = false
    private(set) var errorMessage: String?
    private(set) var receiptError: String?
    private(set) var savedEntry: JobCostEntry?
    private(set) var savedRevision = 0
    private(set) var nextCursor: String?
    private(set) var includesVoided = false
    private(set) var canEdit = false
    private var scope: EstimateDraftScope?
    private var revision = 0
    private let service: any JobCostServing
    private let journal: any JobCostJournaling

    init(projectId: String, service: any JobCostServing, journal: any JobCostJournaling) {
        self.projectId = projectId
        self.service = service
        self.journal = journal
    }

    var canAdd: Bool { canEdit && !isLoading && !isWorking && !journalNeedsAttention && pending == nil }

    func load(scope: EstimateDraftScope, canEdit: Bool, includeVoided: Bool = false) async {
        guard !isWorking else { return }
        if self.scope != scope {
            self.scope = scope
            entries = []
            summary = nil
            pending = nil
            savedEntry = nil
            receiptError = nil
            journalNeedsAttention = false
        }
        revision += 1
        let requestRevision = revision
        self.canEdit = canEdit
        includesVoided = includeVoided
        isLoading = true
        defer { if revision == requestRevision { isLoading = false } }
        do {
            let page = try await service.list(projectId: projectId, cursor: nil, includeVoided: includeVoided)
            try validate(page)
            try Task.checkCancellation()
            guard revision == requestRevision else { return }
            entries = page.items
            summary = page.summary
            nextCursor = page.nextCursor
            let stored = try await journal.load(scope: scope, projectId: projectId)
            guard stored == nil || (stored?.scope == scope && stored?.projectId == projectId), revision == requestRevision else { throw JobCostError.invalidJournal }
            pending = stored
            journalNeedsAttention = false
            errorMessage = nil
            if let stored, let matching = entries.first(where: { $0.requestId.lowercased() == stored.request.requestId.lowercased() }) {
                try await confirm(matching, pending: stored)
                if stored.receiptExpected == true, matching.receiptFilename == nil {
                    savedEntry = matching
                    receiptError = "The cost is saved. Choose its receipt again to attach it; receipt files aren't stored in the recovery journal."
                }
            }
        } catch {
            guard revision == requestRevision, !Task.isCancelled else { return }
            journalNeedsAttention = true
            errorMessage = "Recorded costs couldn't be refreshed safely. Retry before adding another cost. \(error.localizedDescription)"
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, !isLoading, !isWorking else { return }
        isLoadingMore = true
        let requestRevision = revision
        defer { isLoadingMore = false }
        do {
            let page = try await service.list(projectId: projectId, cursor: cursor, includeVoided: includesVoided)
            try validate(page)
            guard revision == requestRevision else { return }
            guard page.nextCursor != cursor else { throw JobCostError.invalidResponse }
            let known = Set(entries.map(\.id))
            entries.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
            summary = page.summary
        } catch {
            if !Task.isCancelled { errorMessage = "More costs couldn't be loaded. \(error.localizedDescription)" }
        }
    }

    func save(draft: JobCostDraft, receipt: JobCostReceiptAttachment?) async -> Bool {
        guard !isWorking, !isLoading, canEdit, !journalNeedsAttention, let scope else { return false }
        if pending != nil { return await retryPending(receipt: receipt) }
        guard canAdd, let request = draft.request(id: UUID().uuidString.lowercased()) else {
            errorMessage = draft.validationMessage ?? "Review the cost details before saving."
            return false
        }
        if let validation = receipt?.validationMessage { errorMessage = validation; return false }
        let value = JobCostPending(scope: scope, projectId: projectId, request: request, receiptExpected: receipt != nil)
        isWorking = true
        receiptError = nil
        defer { isWorking = false }
        do {
            try await journal.save(value)
            pending = value
        } catch {
            errorMessage = "The cost wasn't sent because its recovery copy couldn't be saved. Check device storage and try again."
            return false
        }
        return await send(value, receipt: receipt)
    }

    func retryPending(receipt: JobCostReceiptAttachment? = nil) async -> Bool {
        guard !isWorking, !isLoading, canEdit, !journalNeedsAttention, let pending else { return false }
        isWorking = true
        defer { isWorking = false }
        return await send(pending, receipt: receipt)
    }

    func attachReceipt(to entry: JobCostEntry, attachment: JobCostReceiptAttachment) async -> Bool {
        guard canEdit, !isWorking, entry.projectId == projectId, entry.voidedAt == nil else { return false }
        if let validation = attachment.validationMessage { receiptError = validation; return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.attachReceipt(id: entry.id, data: attachment.data, mimeType: attachment.mimeType, filename: attachment.filename)
            receiptError = nil
            savedEntry = nil
            savedRevision &+= 1
            return true
        } catch {
            savedEntry = entry
            receiptError = "The cost is saved, but the receipt couldn't be confirmed. Review its attachment or try attaching it again. \(error.localizedDescription)"
            return false
        }
    }

    func voidEntry(_ entry: JobCostEntry) async -> Bool {
        guard canEdit, !isWorking, entry.projectId == projectId, entry.voidedAt == nil else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.voidEntry(id: entry.id)
            savedRevision &+= 1
            errorMessage = nil
            return true
        } catch {
            errorMessage = "The void couldn't be confirmed. Refresh the history before trying again. \(error.localizedDescription)"
            return false
        }
    }

    func receiptData(for entry: JobCostEntry) async throws -> Data {
        guard entry.projectId == projectId, entries.contains(where: { $0.id == entry.id }) || savedEntry?.id == entry.id else {
            throw JobCostError.invalidResponse
        }
        let data = try await service.receipt(id: entry.id)
        guard !data.isEmpty, data.count <= 5_000_000 else { throw JobCostError.validation("The receipt is outside the supported size.") }
        return data
    }

    private func send(_ value: JobCostPending, receipt: JobCostReceiptAttachment?) async -> Bool {
        guard value.scope == scope, value.projectId == projectId else { return false }
        do {
            let entry = try await service.create(projectId: projectId, request: value.request)
            try await confirm(entry, pending: value)
            savedEntry = entry
            if (includesVoided || entry.voidedAt == nil), !entries.contains(where: { $0.id == entry.id }) { entries.insert(entry, at: 0) }
            if let receipt, entry.receiptFilename == nil, entry.voidedAt == nil {
                do {
                    try await service.attachReceipt(id: entry.id, data: receipt.data, mimeType: receipt.mimeType, filename: receipt.filename)
                    receiptError = nil
                } catch {
                    receiptError = "The cost is saved, but its receipt wasn't attached. Retry the attachment without recording the cost again."
                }
            } else if value.receiptExpected == true, entry.receiptFilename == nil, entry.voidedAt == nil {
                receiptError = "The cost is saved. Choose the receipt again to attach it."
            }
            errorMessage = nil
            return true
        } catch {
            let unconfirmed = (error as? any EstimateCreationFailureClassifying)?.creationWriteIsUnconfirmed ?? true
            if !unconfirmed {
                do { try await journal.remove(scope: value.scope, projectId: projectId); pending = nil }
                catch { journalNeedsAttention = true }
                errorMessage = "The cost wasn't recorded. \(error.localizedDescription)"
            } else {
                errorMessage = "The cost couldn't be confirmed. Its details are locked; check saved costs or retry the same request to avoid a duplicate."
            }
            return false
        }
    }

    private func confirm(_ entry: JobCostEntry, pending value: JobCostPending) async throws {
        let expected = value.request
        guard entry.projectId == projectId, entry.requestId.lowercased() == expected.requestId.lowercased(),
              entry.category == expected.category, entry.description == expected.description,
              entry.currencyCode == expected.currencyCode,
              entry.laborHours == expected.laborHours, entry.hourlyRate == expected.hourlyRate,
              abs(entry.recordedAt.timeIntervalSince(expected.recordedAt)) < 0.001 else { throw JobCostError.invalidResponse }
        if let amount = expected.amount, amount != entry.amount { throw JobCostError.invalidResponse }
        try await journal.remove(scope: value.scope, projectId: projectId)
        pending = nil
        savedEntry = entry
        errorMessage = nil
        savedRevision &+= 1
    }

    private func validate(_ page: JobCostPage) throws {
        guard page.items.allSatisfy({ $0.projectId == projectId }) else { throw JobCostError.invalidResponse }
    }
}
