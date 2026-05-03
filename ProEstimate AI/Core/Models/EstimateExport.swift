import Foundation

/// A snapshot of a previously rendered estimate PDF, persisted server-side
/// so the contractor can re-download or share past versions from the
/// project detail screen without regenerating.
///
/// `pdfData` itself is never returned in API responses — `downloadURL`
/// points to the public binary endpoint, fetched on demand.
struct EstimateExport: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let estimateId: String
    let projectId: String
    let fileName: String
    let contentType: String
    let fileSize: Int
    let downloadURL: URL
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId = "estimate_id"
        case projectId = "project_id"
        case fileName = "file_name"
        case contentType = "content_type"
        case fileSize = "file_size"
        case downloadURL = "download_url"
        case createdAt = "created_at"
    }
}
