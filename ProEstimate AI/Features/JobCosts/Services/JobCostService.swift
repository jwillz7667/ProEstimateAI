import Foundation

struct JobCostService: JobCostServing {
    let apiClient: any APIClientProtocol
    private let sessionId: UUID
    init(apiClient: any APIClientProtocol = APIClient.shared) { self.apiClient = apiClient; sessionId = TokenStore.shared.sessionIdentifier }
    func list(projectId: String, cursor: String?, includeVoided: Bool = false) async throws -> JobCostPage {
        try requireSession()
        return try await apiClient.request(.listJobCosts(projectId: projectId, cursor: cursor, includeVoided: includeVoided))
    }
    func create(projectId: String, request: JobCostRequest) async throws -> JobCostEntry {
        try requireSession()
        return try await apiClient.request(.createJobCost(projectId: projectId, body: request))
    }
    func voidEntry(id: String) async throws { try requireSession(); try await apiClient.request(.voidJobCost(id: id)) as Void }
    func attachReceipt(id: String, data: Data, mimeType: String, filename: String) async throws {
        try requireSession()
        struct Body: Encodable, Sendable { let data_base64: String; let mime_type: String; let filename: String }
        try await apiClient.request(.uploadJobCostReceipt(id: id, body: Body(data_base64: data.base64EncodedString(), mime_type: mimeType, filename: filename))) as Void
    }
    func receipt(id: String) async throws -> Data { try requireSession(); return try await apiClient.requestData(.getJobCostReceipt(id: id)) }
    private func requireSession() throws {
        try Task.checkCancellation()
        guard TokenStore.shared.sessionIdentifier == sessionId else { throw APIError.unauthorized }
    }
}
