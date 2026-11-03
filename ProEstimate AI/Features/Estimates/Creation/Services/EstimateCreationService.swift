import Foundation

struct EstimateCreationService: EstimateCreationServing {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func listClients() async throws -> [Client] {
        try await apiClient.requestAllPages { .listClients(cursor: $0) }
    }

    func createProject(request: ProjectCreationRequest) async throws -> Project {
        try await apiClient.request(.createProject(body: request))
    }

    func createEstimate(projectId: String, title: String, method: EstimateCreationMethod) async throws -> Estimate {
        let body = EstimateCreationBody(projectId: projectId, title: method == .manual ? title : nil)
        switch method {
        case .manual: return try await apiClient.request(.createEstimate(body: body))
        case .ai: return try await apiClient.request(.generateAIEstimate(body: body))
        case .template: throw APIError.validation(fields: ["template_id": ["Choose an estimate template."]])
        }
    }

    func createEstimateFromTemplate(projectId: String, title: String, templateId: String, requestId: String) async throws -> Estimate {
        try await apiClient.request(.instantiateEstimateTemplate(id: templateId,
            body: EstimateTemplateCreationBody(projectId: projectId, title: title, requestId: requestId)))
    }

    func listEstimates(projectId: String) async throws -> [Estimate] {
        try await apiClient.request(.listEstimates(projectId: projectId))
    }
}

private struct EstimateTemplateCreationBody: Encodable, Sendable {
    let projectId: String
    let title: String
    let requestId: String
    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title
        case requestId = "request_id"
    }
}

struct EstimateCreationBody: Encodable, Sendable {
    let projectId: String
    let title: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title
    }
}

extension APIError: EstimateCreationFailureClassifying {
    nonisolated var creationWriteIsUnconfirmed: Bool {
        switch self {
        case .network, .decoding, .unknown: true
        case let .server(code, _): ["INTERNAL_ERROR", "SERVICE_UNAVAILABLE", "TIMEOUT"].contains(code)
        case .unauthorized, .paywall, .validation: false
        }
    }
}
