import Foundation

/// Represents a single AI remodel preview generation request and its result.
/// Generations are enqueued by the backend and processed asynchronously.
/// The client polls or receives push updates for status changes.
struct AIGeneration: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String
    let prompt: String
    let status: Status
    let previewURL: URL?
    let thumbnailURL: URL?
    let generationDurationMs: Int?
    let errorMessage: String?
    let createdAt: Date

    // MARK: - Nested Enums

    /// Tracks the lifecycle of an AI generation job.
    enum Status: String, Codable, CaseIterable, Sendable {
        case queued
        case processing
        case completed
        case failed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case prompt
        case status
        case previewURL = "preview_url"
        case thumbnailURL = "thumbnail_url"
        case generationDurationMs = "generation_duration_ms"
        case errorMessage = "error_message"
        case createdAt = "created_at"
    }
}

// MARK: - Convenience

extension AIGeneration {
    /// Whether the generation is still in progress.
    var isInProgress: Bool {
        status == .queued || status == .processing
    }

    /// Formatted generation duration, e.g. "2.4s".
    var durationDisplay: String? {
        guard let ms = generationDurationMs else { return nil }
        let seconds = Double(ms) / 1000.0
        return String(format: "%.1fs", seconds)
    }
}

// MARK: - Sample Data

extension AIGeneration {
    static let sample = AIGeneration(
        id: "gen-001",
        projectId: "p-001",
        prompt: "Modern kitchen with white shaker cabinets and quartz countertops",
        status: .completed,
        previewURL: URL(string: "https://cdn.proestimate.ai/gen/gen-001.jpg"),
        thumbnailURL: URL(string: "https://cdn.proestimate.ai/gen/gen-001-thumb.jpg"),
        generationDurationMs: 2400,
        errorMessage: nil,
        createdAt: Date()
    )
}
