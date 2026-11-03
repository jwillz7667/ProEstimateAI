import Foundation
import Observation

struct ChangeOrderPending: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let scope: EstimateDraftScope
    let resourceId: String
    let create: CreateChangeOrderRequest?
    let apply: ApplyChangeOrderRequest?
    var isValid: Bool {
        schemaVersion == 1 && !resourceId.isEmpty && (create == nil || (!create!.title.isEmpty && create!.title.utf16.count <= 200 && !create!.reason.isEmpty && create!.reason.utf16.count <= 10_000)) && ((create != nil && apply == nil && create?.baseEstimateId == resourceId && UUID(uuidString: create!.requestId) != nil) || (apply != nil && create == nil && UUID(uuidString: apply!.requestId) != nil))
    }
}
protocol ChangeOrderJournaling: Sendable {
    func load(scope: EstimateDraftScope, resourceId: String) async throws -> ChangeOrderPending?
    func save(_ pending: ChangeOrderPending) async throws
    func remove(scope: EstimateDraftScope, resourceId: String) async throws
}
@MainActor final class ChangeOrderJournal: ChangeOrderJournaling {
    private let store: EstimateDraftStore
    private var sessions: [EstimateDraftScope: UUID] = [:]
    init(store: EstimateDraftStore = .shared) { self.store = store }
    private func session(_ scope: EstimateDraftScope) async throws -> UUID {
        if let id = sessions[scope] { return id }
        let id = try await store.openSession(scope: scope); sessions[scope] = id; return id
    }
    func load(scope: EstimateDraftScope, resourceId: String) async throws -> ChangeOrderPending? {
        _ = try await session(scope)
        guard let data = try await store.loadJournal(scope: scope, namespace: "change-orders", recordId: resourceId) else { return nil }
        return try JSONDecoder().decode(ChangeOrderPending.self, from: data)
    }
    func save(_ pending: ChangeOrderPending) async throws {
        guard pending.isValid else { throw ChangeOrderError.invalidRecovery }
        let sessionId = try await session(pending.scope)
        try await store.saveJournal(JSONEncoder().encode(pending), scope: pending.scope, namespace: "change-orders", recordId: pending.resourceId, sessionId: sessionId)
    }
    func remove(scope: EstimateDraftScope, resourceId: String) async throws {
        let sessionId = try await session(scope)
        try await store.removeJournal(scope: scope, namespace: "change-orders", recordId: resourceId, sessionId: sessionId)
    }
}

/// Freeze and protect the exact body before any write. A lost response can
/// only retry the same UUID; new input never replaces an unresolved request.
@MainActor @Observable
final class ChangeOrderMutationModel {
    private(set) var pending: ChangeOrderPending?
    private(set) var result: ChangeOrder?
    private(set) var isWorking = false
    private(set) var isReady = false
    private(set) var errorMessage: String?
    private(set) var lastError: Error?
    private var scope: EstimateDraftScope?
    private var resourceId: String?
    private let service: any ChangeOrderServing
    private let journal: any ChangeOrderJournaling
    init(service: any ChangeOrderServing, journal: any ChangeOrderJournaling) { self.service = service; self.journal = journal }
    func restore(scope: EstimateDraftScope, resourceId: String) async {
        guard !isWorking else { return }
        if self.scope != scope || self.resourceId != resourceId { result = nil; pending = nil }
        self.scope = scope; self.resourceId = resourceId; isReady = false
        do {
            let restored = try await journal.load(scope: scope, resourceId: resourceId)
            guard restored == nil || (restored?.scope == scope && restored?.resourceId == resourceId && restored?.isValid == true) else { throw ChangeOrderError.invalidRecovery }
            pending = restored; isReady = true; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func create(title: String, reason: String) async {
        guard isReady, !isWorking, let scope, let resourceId else { return }
        if pending != nil { await retry(); return }
        do {
            let request = try CreateChangeOrderRequest.validated(baseEstimateId: resourceId, title: title, reason: reason)
            try await save(ChangeOrderPending(scope: scope, resourceId: resourceId, create: request, apply: nil))
            await retry()
        } catch { errorMessage = error.localizedDescription }
    }
    func apply() async {
        guard isReady, !isWorking, let scope, let resourceId else { return }
        if pending != nil { await retry(); return }
        do {
            try await save(ChangeOrderPending(scope: scope, resourceId: resourceId, create: nil, apply: ApplyChangeOrderRequest(requestId: UUID().uuidString.lowercased())))
            await retry()
        } catch { errorMessage = error.localizedDescription }
    }
    private func save(_ request: ChangeOrderPending) async throws {
        try await journal.save(request)
        pending = request
    }
    func retry() async {
        guard isReady, !isWorking, let pending, pending.isValid else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let saved: ChangeOrder
            if let request = pending.create { saved = try await service.create(request) }
            else if let request = pending.apply { saved = try await service.apply(id: pending.resourceId, request: request) }
            else { throw ChangeOrderError.invalidRecovery }
            guard saved.estimate.companyId == pending.scope.companyId, saved.projectId == saved.estimate.projectId, saved.estimateId == saved.estimate.id, (pending.create == nil ? (saved.id == pending.resourceId && ["applied", "included"].contains(saved.status)) : saved.baseEstimateId == pending.resourceId) else { throw ChangeOrderError.invalidResponse }
            try Task.checkCancellation()
            result = saved
            try await journal.remove(scope: pending.scope, resourceId: pending.resourceId)
            self.pending = nil; errorMessage = nil
            AppEventBus.shared.noteProjectChange()
        } catch {
            // A confirmed server rejection can release the frozen request.
            // Transport/decoding/unknown failures keep it for exact replay.
            if let classified = error as? any EstimateCreationFailureClassifying, !classified.creationWriteIsUnconfirmed, result == nil {
                do { try await journal.remove(scope: pending.scope, resourceId: pending.resourceId); self.pending = nil } catch { }
            }
            lastError = error
            errorMessage = error.localizedDescription
        }
    }
}
