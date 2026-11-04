import Foundation

struct FollowUpService: FollowUpServing {
    private let api: any APIClientProtocol
    init(api: any APIClientProtocol = APIClient.shared) { self.api = api }

    func history(kind: FollowUpKind, entityId: String) async throws -> FollowUpHistory {
        try await api.request(.getFollowUpHistory(kind: kind.rawValue, entityId: entityId))
    }
    func queue(_ request: QueueFollowUpRequest) async throws -> FollowUpRecord {
        try await api.request(.queueFollowUp(body: request))
    }
    func settings() async throws -> FollowUpSettings {
        try await api.request(.getFollowUpSettings)
    }
    func updateSettings(_ request: UpdateFollowUpSettings) async throws -> FollowUpSettings {
        try await api.request(.updateFollowUpSettings(body: request))
    }
}
