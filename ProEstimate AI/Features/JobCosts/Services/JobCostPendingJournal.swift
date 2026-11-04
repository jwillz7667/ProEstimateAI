import Foundation

protocol JobCostJournaling: Sendable {
    func load(scope: EstimateDraftScope, projectId: String) async throws -> JobCostPending?
    func save(_ pending: JobCostPending) async throws
    func remove(scope: EstimateDraftScope, projectId: String) async throws
}

@MainActor
final class JobCostPendingJournal: JobCostJournaling {
    private let store: EstimateDraftStore
    private var sessions: [EstimateDraftScope: UUID] = [:]
    init(store: EstimateDraftStore = .shared) { self.store = store }

    func load(scope: EstimateDraftScope, projectId: String) async throws -> JobCostPending? {
        _ = try await session(scope)
        guard let data = try await store.loadJournal(scope: scope, namespace: "job-cost", recordId: projectId) else { return nil }
        let value = try JSONDecoder().decode(JobCostPending.self, from: data)
        let timestamp = value.request.recordedAt.timeIntervalSince1970
        guard value.schemaVersion == 1, value.scope == scope, value.projectId == projectId,
              UUID(uuidString: value.request.requestId) != nil, timestamp.isFinite, floor(timestamp) == timestamp,
              JobCostDraft(request: value.request).validationMessage == nil else { throw JobCostError.invalidJournal }
        return value
    }

    func save(_ pending: JobCostPending) async throws {
        let id = try await session(pending.scope)
        let data = try JSONEncoder().encode(pending)
        try await store.saveJournal(data, scope: pending.scope, namespace: "job-cost", recordId: pending.projectId, sessionId: id)
    }

    func remove(scope: EstimateDraftScope, projectId: String) async throws {
        let id = try await session(scope)
        try await store.removeJournal(scope: scope, namespace: "job-cost", recordId: projectId, sessionId: id)
    }

    private func session(_ scope: EstimateDraftScope) async throws -> UUID {
        if let id = sessions[scope] { return id }
        let id = try await store.openSession(scope: scope)
        sessions[scope] = id
        return id
    }
}
