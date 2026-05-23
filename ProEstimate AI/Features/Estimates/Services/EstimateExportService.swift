import Foundation

// MARK: - Upload Body

/// Body sent to `POST /v1/estimates/:estimateId/exports` when persisting
/// a freshly rendered PDF. `pdfData` is the raw base64 string.
struct EstimateExportUploadBody: Encodable, Sendable {
    let fileName: String
    let contentType: String
    let pdfData: String

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case contentType = "content_type"
        case pdfData = "pdf_data"
    }
}

// MARK: - Protocol

protocol EstimateExportServiceProtocol: Sendable {
    func listByEstimate(estimateId: String) async throws -> [EstimateExport]
    func listByProject(projectId: String) async throws -> [EstimateExport]
    func upload(estimateId: String, fileName: String, pdfData: Data) async throws -> EstimateExport
    func delete(id: String) async throws
}

// MARK: - Mock Implementation

final class MockEstimateExportService: EstimateExportServiceProtocol {
    private let simulatedDelay: UInt64 = 300_000_000

    func listByEstimate(estimateId: String) async throws -> [EstimateExport] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleExports.filter { $0.estimateId == estimateId }
    }

    func listByProject(projectId: String) async throws -> [EstimateExport] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleExports.filter { $0.projectId == projectId }
    }

    func upload(estimateId: String, fileName: String, pdfData: Data) async throws -> EstimateExport {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return EstimateExport(
            id: "ex-\(UUID().uuidString.prefix(8))",
            estimateId: estimateId,
            projectId: "p-mock",
            fileName: fileName,
            contentType: "application/pdf",
            fileSize: pdfData.count,
            downloadURL: URL(string: "https://example.invalid/mock.pdf")!,
            createdAt: Date()
        )
    }

    func delete(id _: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }

    private static let sampleExports: [EstimateExport] = []
}
