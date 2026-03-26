import Foundation

/// Represents a single activity event within a project timeline.
/// Activity logs provide an audit trail of all significant actions —
/// from project creation through invoice payment.
struct ActivityLogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String
    let userId: String?
    let action: Action
    let description: String
    let createdAt: Date

    // MARK: - Nested Enums

    /// All trackable actions within the project lifecycle.
    enum Action: String, Codable, CaseIterable, Sendable {
        case created
        case updated
        case statusChanged = "status_changed"
        case imageUploaded = "image_uploaded"
        case generationStarted = "generation_started"
        case generationCompleted = "generation_completed"
        case estimateCreated = "estimate_created"
        case estimateUpdated = "estimate_updated"
        case proposalSent = "proposal_sent"
        case proposalViewed = "proposal_viewed"
        case proposalApproved = "proposal_approved"
        case proposalDeclined = "proposal_declined"
        case invoiceCreated = "invoice_created"
        case invoiceSent = "invoice_sent"
        case invoicePaid = "invoice_paid"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case userId = "user_id"
        case action
        case description
        case createdAt = "created_at"
    }
}

// MARK: - Convenience

extension ActivityLogEntry {
    /// SF Symbol name for the action, used in timeline UI.
    var systemImage: String {
        switch action {
        case .created: return "plus.circle"
        case .updated: return "pencil.circle"
        case .statusChanged: return "arrow.right.circle"
        case .imageUploaded: return "photo.circle"
        case .generationStarted: return "sparkles"
        case .generationCompleted: return "checkmark.circle"
        case .estimateCreated: return "doc.badge.plus"
        case .estimateUpdated: return "doc.badge.arrow.up"
        case .proposalSent: return "paperplane"
        case .proposalViewed: return "eye"
        case .proposalApproved: return "hand.thumbsup"
        case .proposalDeclined: return "hand.thumbsdown"
        case .invoiceCreated: return "dollarsign.circle"
        case .invoiceSent: return "paperplane.fill"
        case .invoicePaid: return "checkmark.seal"
        }
    }
}

// MARK: - Sample Data

extension ActivityLogEntry {
    static let sample = ActivityLogEntry(
        id: "log-001",
        projectId: "p-001",
        userId: "u-001",
        action: .created,
        description: "Project created",
        createdAt: Date()
    )

    /// Collection of sample entries for previews and mock data.
    static let samples: [ActivityLogEntry] = [
        ActivityLogEntry(
            id: "act-001",
            projectId: "p-001",
            userId: "u-001",
            action: .created,
            description: "Kitchen Remodel project was created",
            createdAt: Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        ),
        ActivityLogEntry(
            id: "act-002",
            projectId: "p-001",
            userId: "u-001",
            action: .imageUploaded,
            description: "4 photos were uploaded",
            createdAt: Calendar.current.date(byAdding: .day, value: -4, to: Date())!
        ),
        ActivityLogEntry(
            id: "act-003",
            projectId: "p-001",
            userId: nil,
            action: .generationCompleted,
            description: "Generation completed in 2.4s",
            createdAt: Calendar.current.date(byAdding: .day, value: -4, to: Date())!
        ),
        ActivityLogEntry(
            id: "act-004",
            projectId: "p-001",
            userId: "u-001",
            action: .estimateCreated,
            description: "EST-1001 v1 — $22,732.50",
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        ),
    ]
}
