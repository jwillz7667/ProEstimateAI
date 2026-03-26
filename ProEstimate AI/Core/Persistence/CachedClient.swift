import Foundation
import SwiftData

/// SwiftData model for offline caching of clients.
/// Stores contact essentials plus the complete JSON payload
/// so the client picker and detail views work without connectivity.
@Model
final class CachedClient {
    @Attribute(.unique) var clientId: String
    var name: String
    var email: String?
    var phone: String?
    var lastSyncedAt: Date
    var jsonPayload: Data

    init(
        clientId: String,
        name: String,
        email: String? = nil,
        phone: String? = nil,
        lastSyncedAt: Date = Date(),
        jsonPayload: Data = Data()
    ) {
        self.clientId = clientId
        self.name = name
        self.email = email
        self.phone = phone
        self.lastSyncedAt = lastSyncedAt
        self.jsonPayload = jsonPayload
    }
}
