import Foundation

/// Represents a media asset attached to a project — original photos,
/// AI-generated previews, or supporting documents.
struct Asset: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String
    let url: URL
    let thumbnailURL: URL?
    let assetType: AssetType
    let sortOrder: Int
    let createdAt: Date

    // MARK: - Nested Enums

    /// Distinguishes between user-uploaded originals, AI outputs, and documents.
    enum AssetType: String, Codable, CaseIterable, Sendable {
        case original
        case aiGenerated = "ai_generated"
        case document
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case url
        case thumbnailURL = "thumbnail_url"
        case assetType = "asset_type"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

// MARK: - Sample Data

extension Asset {
    static let sample = Asset(
        id: "a-001",
        projectId: "p-001",
        url: URL(string: "https://cdn.proestimate.ai/assets/a-001.jpg")!,
        thumbnailURL: URL(string: "https://cdn.proestimate.ai/assets/a-001-thumb.jpg")!,
        assetType: .original,
        sortOrder: 0,
        createdAt: Date()
    )
}
