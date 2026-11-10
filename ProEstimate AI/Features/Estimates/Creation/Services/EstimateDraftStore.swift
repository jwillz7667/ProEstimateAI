import Foundation
import CryptoKit

/// A local work-in-progress journal, never an offline claim of a server save.
/// Files are account/company scoped, atomic, excluded from backups and protected
/// while the iOS device is locked. API keys and authentication tokens are absent.
actor EstimateDraftStore: EstimateDraftPersisting {
    static let shared = EstimateDraftStore()
    private let directory: URL
    private var sessions: [EstimateDraftScope: Set<UUID>] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProEstimateAI/EstimateDrafts", isDirectory: true)
    }

    func openSession(scope: EstimateDraftScope) async throws -> UUID {
        try Task.checkCancellation()
        guard !scope.userId.isEmpty, !scope.companyId.isEmpty else { throw EstimateDraftStoreError.invalidCheckpoint }
        let id = UUID()
        sessions[scope, default: []].insert(id)
        return id
    }

    func load(scope: EstimateDraftScope) async throws -> EstimateDraftCheckpoint? {
        try Task.checkCancellation()
        let file = try fileURL(scope: scope)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 1_000_000 else {
            throw EstimateDraftStoreError.invalidCheckpoint
        }
        let data = try Data(contentsOf: file)
        let checkpoint = try await Self.decode(data)
        guard checkpoint.schemaVersion == 1, checkpoint.scope == scope,
              (checkpoint.project?.companyId ?? scope.companyId) == scope.companyId,
              (checkpoint.estimate?.companyId ?? scope.companyId) == scope.companyId,
              checkpoint.estimate?.id == nil || checkpoint.estimate?.projectId == checkpoint.project?.id,
              UUID(uuidString: checkpoint.templateRequestId) != nil else {
            throw EstimateDraftStoreError.invalidCheckpoint
        }
        switch checkpoint.phase {
        case .projectSaved, .estimateWritePending:
            guard checkpoint.project?.id != nil else { throw EstimateDraftStoreError.invalidCheckpoint }
        case .estimateSaved:
            guard checkpoint.project?.id != nil, checkpoint.estimate?.id != nil else { throw EstimateDraftStoreError.invalidCheckpoint }
        case .draft, .projectWritePending: break
        }
        return checkpoint
    }

    func save(_ checkpoint: EstimateDraftCheckpoint, sessionId: UUID) async throws {
        try Task.checkCancellation()
        guard sessions[checkpoint.scope]?.contains(sessionId) == true, checkpoint.schemaVersion == 1,
              (checkpoint.project?.companyId ?? checkpoint.scope.companyId) == checkpoint.scope.companyId else {
            throw EstimateDraftStoreError.invalidCheckpoint
        }
        let file = try fileURL(scope: checkpoint.scope)
        let accountDirectory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: accountDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = accountDirectory
        try folder.setResourceValues(values)
        let data = try await Self.encode(checkpoint)
        try Task.checkCancellation()
        guard sessions[checkpoint.scope]?.contains(sessionId) == true else { throw EstimateDraftStoreError.invalidCheckpoint }
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove(scope: EstimateDraftScope, sessionId: UUID) async throws {
        try Task.checkCancellation()
        guard sessions[scope]?.contains(sessionId) == true else { throw EstimateDraftStoreError.invalidCheckpoint }
        let file = try fileURL(scope: scope)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    /// Revoke active writer sessions before deleting files so an old view's
    /// queued autosave cannot recreate private drafts after sign-out.
    func purge(userId: String) async throws {
        sessions = sessions.filter { $0.key.userId != userId }
        let folder = directory.appendingPathComponent(digest(userId), isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    /// Small account-scoped journals share the same protection and sign-out
    /// revocation as estimate drafts. Namespace and record IDs are hashed.
    func loadJournal(scope: EstimateDraftScope, namespace: String, recordId: String) async throws -> Data? {
        try Task.checkCancellation()
        let file = try journalURL(scope: scope, namespace: namespace, recordId: recordId)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 1_000_000 else { throw EstimateDraftStoreError.invalidCheckpoint }
        return try Data(contentsOf: file)
    }

    func saveJournal(_ data: Data, scope: EstimateDraftScope, namespace: String, recordId: String, sessionId: UUID) async throws {
        try Task.checkCancellation()
        guard sessions[scope]?.contains(sessionId) == true, data.count <= 1_000_000 else { throw EstimateDraftStoreError.invalidCheckpoint }
        let file = try journalURL(scope: scope, namespace: namespace, recordId: recordId)
        var folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func removeJournal(scope: EstimateDraftScope, namespace: String, recordId: String, sessionId: UUID) async throws {
        try Task.checkCancellation()
        guard sessions[scope]?.contains(sessionId) == true else { throw EstimateDraftStoreError.invalidCheckpoint }
        let file = try journalURL(scope: scope, namespace: namespace, recordId: recordId)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func journalURL(scope: EstimateDraftScope, namespace: String, recordId: String) throws -> URL {
        guard !scope.userId.isEmpty, !scope.companyId.isEmpty, !namespace.isEmpty, !recordId.isEmpty else {
            throw EstimateDraftStoreError.invalidCheckpoint
        }
        return directory.appendingPathComponent(digest(scope.userId), isDirectory: true)
            .appendingPathComponent(digest(scope.companyId), isDirectory: true)
            .appendingPathComponent(digest(namespace), isDirectory: true)
            .appendingPathComponent(digest(recordId)).appendingPathExtension("json")
    }

    private func fileURL(scope: EstimateDraftScope) throws -> URL {
        guard !scope.userId.isEmpty, !scope.companyId.isEmpty else { throw EstimateDraftStoreError.invalidCheckpoint }
        return directory.appendingPathComponent(digest(scope.userId), isDirectory: true)
            .appendingPathComponent(digest(scope.companyId)).appendingPathExtension("json")
    }

    private func digest(_ identity: String) -> String {
        SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // Existing app DTOs use main-actor Codable conformance. Their small bounded
    // JSON conversion stays with those DTOs; all filesystem work remains here.
    @MainActor private static func encode(_ checkpoint: EstimateDraftCheckpoint) throws -> Data {
        try JSONEncoder().encode(checkpoint)
    }

    @MainActor private static func decode(_ data: Data) throws -> EstimateDraftCheckpoint {
        try JSONDecoder().decode(EstimateDraftCheckpoint.self, from: data)
    }
}

private enum EstimateDraftStoreError: LocalizedError {
    case invalidCheckpoint
    nonisolated var errorDescription: String? { "The saved draft couldn't be matched to this account and company." }
}
