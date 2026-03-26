import Foundation

/// Production implementation of `GenerationServiceProtocol` that delegates
/// AI generation operations to the backend REST API via `APIClient`.
final class LiveGenerationService: GenerationServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - GenerationServiceProtocol

    func startGeneration(projectId: String, prompt: String) async throws -> AIGeneration {
        let body = GenerationRequestBody(prompt: prompt)
        return try await apiClient.request(
            .createGeneration(projectId: projectId, body: body)
        )
    }

    func getGenerationStatus(id: String) async throws -> AIGeneration {
        try await apiClient.request(.getGeneration(id: id))
    }

    func listGenerations(projectId: String) async throws -> [AIGeneration] {
        try await apiClient.request(.listGenerations(projectId: projectId))
    }
}

// MARK: - Request Body

/// Body for the POST /projects/:id/generations endpoint.
/// The encoder uses `.convertToSnakeCase`, so `prompt` stays as `"prompt"`.
private struct GenerationRequestBody: Encodable, Sendable {
    let prompt: String
}
