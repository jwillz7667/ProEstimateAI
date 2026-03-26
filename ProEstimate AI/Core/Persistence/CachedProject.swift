import Foundation
import SwiftData

/// SwiftData model for offline caching of projects.
/// Stores a lightweight summary plus the full JSON payload
/// so the app can render project lists and details without network access.
@Model
final class CachedProject {
    @Attribute(.unique) var projectId: String
    var title: String
    var projectType: String
    var status: String
    var clientName: String?
    var thumbnailData: Data?
    var totalAmount: Decimal?
    var lastSyncedAt: Date
    var jsonPayload: Data // Full Project JSON for offline access

    init(
        projectId: String,
        title: String,
        projectType: String,
        status: String,
        clientName: String? = nil,
        thumbnailData: Data? = nil,
        totalAmount: Decimal? = nil,
        lastSyncedAt: Date = Date(),
        jsonPayload: Data = Data()
    ) {
        self.projectId = projectId
        self.title = title
        self.projectType = projectType
        self.status = status
        self.clientName = clientName
        self.thumbnailData = thumbnailData
        self.totalAmount = totalAmount
        self.lastSyncedAt = lastSyncedAt
        self.jsonPayload = jsonPayload
    }
}
