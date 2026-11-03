import Foundation

nonisolated struct EstimateDraftScope: Codable, Hashable, Sendable {
    let userId: String
    let companyId: String
}

struct EstimateDraftCheckpoint: Codable, Sendable {
    enum Phase: String, Codable, Sendable {
        case draft
        case projectWritePending
        case projectSaved
        case estimateWritePending
        case estimateSaved
    }

    var schemaVersion = 1
    let scope: EstimateDraftScope
    let draft: EstimateCreationDraft
    let selectedClientId: String?
    let project: Project?
    let estimate: Estimate?
    let phase: Phase
    let templateRequestId: String
    let savedAt: Date
}

protocol EstimateDraftPersisting: Sendable {
    func openSession(scope: EstimateDraftScope) async throws -> UUID
    func load(scope: EstimateDraftScope) async throws -> EstimateDraftCheckpoint?
    func save(_ checkpoint: EstimateDraftCheckpoint, sessionId: UUID) async throws
    func remove(scope: EstimateDraftScope, sessionId: UUID) async throws
}
