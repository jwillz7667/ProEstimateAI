import Foundation
import SwiftData

/// SwiftData model for offline caching of estimates.
/// Keeps a denormalized summary (number, status, total) alongside
/// the full JSON so the estimate detail screen works offline.
@Model
final class CachedEstimate {
    @Attribute(.unique) var estimateId: String
    var estimateNumber: String
    var projectId: String
    var status: String
    var totalAmount: Decimal
    var version: Int
    var lastSyncedAt: Date
    var jsonPayload: Data

    init(
        estimateId: String,
        estimateNumber: String,
        projectId: String,
        status: String,
        totalAmount: Decimal,
        version: Int = 1,
        lastSyncedAt: Date = Date(),
        jsonPayload: Data = Data()
    ) {
        self.estimateId = estimateId
        self.estimateNumber = estimateNumber
        self.projectId = projectId
        self.status = status
        self.totalAmount = totalAmount
        self.version = version
        self.lastSyncedAt = lastSyncedAt
        self.jsonPayload = jsonPayload
    }
}
