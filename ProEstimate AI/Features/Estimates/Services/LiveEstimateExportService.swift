import Foundation

/// Production implementation of `EstimateExportServiceProtocol`. Persists
/// rendered estimate PDFs to the backend so they can be re-shared from the
/// project detail screen without regeneration.
final class LiveEstimateExportService: EstimateExportServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func listByEstimate(estimateId: String) async throws -> [EstimateExport] {
        try await apiClient.request(.listEstimateExports(estimateId: estimateId))
    }

    func listByProject(projectId: String) async throws -> [EstimateExport] {
        try await apiClient.request(.listProjectEstimateExports(projectId: projectId))
    }

    func upload(estimateId: String, fileName: String, pdfData: Data) async throws -> EstimateExport {
        let body = EstimateExportUploadBody(
            fileName: fileName,
            contentType: "application/pdf",
            pdfData: pdfData.base64EncodedString()
        )
        return try await apiClient.request(.createEstimateExport(estimateId: estimateId, body: body))
    }

    func delete(id: String) async throws {
        try await apiClient.request(.deleteEstimateExport(id: id)) as Void
    }
}
