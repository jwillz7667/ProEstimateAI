import Foundation

enum FollowUpKind: String, Codable, Sendable { case proposal, invoice }

struct FollowUpRecord: Codable, Identifiable, Sendable {
    let id: String
    let source: String
    let status: String
    let attempts: Int
    let createdAt: Date
    let acceptedAt: Date?
    let deliveredAt: Date?
    let errorMessage: String?
    enum CodingKeys: String, CodingKey {
        case id, source, status, attempts
        case createdAt = "created_at", acceptedAt = "accepted_at", deliveredAt = "delivered_at", errorMessage = "error_message"
    }
    var isPending: Bool { status == "queued" || status == "sending" }
    var statusTitle: String {
        switch status {
        case "queued": "Queued"
        case "sending": "Sending"
        case "sent": "Accepted by email provider"
        case "delivered": "Delivered"
        case "cancelled": "Stopped"
        case "failed": "Could not confirm delivery"
        case "bounced": "Email bounced"
        case "complained": "Recipient reported this email"
        default: "Check delivery status"
        }
    }
}

struct FollowUpHistory: Codable, Sendable {
    let eligible: Bool
    let unavailableReason: String?
    let deliveryAvailable: Bool
    let recipientEmail: String?
    let suppressed: Bool
    let lastContactAt: Date?
    let messages: [FollowUpRecord]
    enum CodingKeys: String, CodingKey {
        case eligible, suppressed, messages
        case unavailableReason = "unavailable_reason", deliveryAvailable = "delivery_available"
        case recipientEmail = "recipient_email", lastContactAt = "last_contact_at"
    }
}

struct FollowUpSettings: Codable, Sendable {
    let enabled: Bool
    let quoteDays: Int
    let invoiceDays: Int
    let enabledAt: Date?
    let deliveryAvailable: Bool
    let canManage: Bool
    enum CodingKeys: String, CodingKey {
        case enabled
        case quoteDays = "quote_days", invoiceDays = "invoice_days", enabledAt = "enabled_at"
        case deliveryAvailable = "delivery_available", canManage = "can_manage"
    }
}

struct QueueFollowUpRequest: Encodable, Sendable {
    let entityKind: FollowUpKind
    let entityId: String
    let requestId: String
    enum CodingKeys: String, CodingKey {
        case entityKind = "entity_kind", entityId = "entity_id", requestId = "request_id"
    }
}

struct UpdateFollowUpSettings: Encodable, Sendable {
    let enabled: Bool
    let quoteDays: Int
    let invoiceDays: Int
    enum CodingKeys: String, CodingKey {
        case enabled, quoteDays = "quote_days", invoiceDays = "invoice_days"
    }
}

protocol FollowUpServing: Sendable {
    func history(kind: FollowUpKind, entityId: String) async throws -> FollowUpHistory
    func queue(_ request: QueueFollowUpRequest) async throws -> FollowUpRecord
    func settings() async throws -> FollowUpSettings
    func updateSettings(_ request: UpdateFollowUpSettings) async throws -> FollowUpSettings
}
