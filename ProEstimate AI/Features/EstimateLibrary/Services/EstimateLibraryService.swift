import Foundation

struct EstimateLibraryService: EstimateLibraryServing {
    private let api: any APIClientProtocol
    init(api: any APIClientProtocol = APIClient.shared) { self.api = api }
    func templates(query: String, cursor: String?) async throws -> EstimateLibraryPage<EstimateTemplate> {
        let page: APIPage<EstimateTemplate> = try await api.requestPage(.listEstimateTemplates(query: query, cursor: cursor))
        return .init(items: page.items, nextCursor: page.nextCursor)
    }
    func items(query: String, cursor: String?) async throws -> EstimateLibraryPage<SavedEstimateLibraryItem> {
        let page: APIPage<SavedEstimateLibraryItem> = try await api.requestPage(.listSavedEstimateItems(query: query, cursor: cursor))
        return .init(items: page.items, nextCursor: page.nextCursor)
    }
    func saveTemplate(_ request: SaveEstimateTemplateRequest) async throws -> EstimateTemplate {
        try await api.request(.saveEstimateTemplate(body: request))
    }
    func saveItem(_ request: SaveEstimateLibraryItemRequest, itemId: String?) async throws -> SavedEstimateLibraryItem {
        if let itemId { return try await api.request(.updateEstimateLibraryItem(id: itemId, body: request)) }
        return try await api.request(.saveEstimateLibraryItem(body: request))
    }
    func applyItem(id: String, request: ApplyEstimateLibraryItemRequest) async throws -> EstimateLineItem {
        try await api.request(.applyEstimateLibraryItem(id: id, body: request))
    }
    func duplicateEstimate(id: String, request: DuplicateEstimateRequest) async throws -> Estimate {
        try await api.request(.duplicateEstimate(id: id, body: request))
    }
    func removeItem(id: String) async throws { try await api.request(.deleteEstimateLibraryItem(id: id)) as Void }
    func removeTemplate(id: String) async throws { try await api.request(.deleteEstimateTemplate(id: id)) as Void }
}

extension APIError: EstimateLibraryFailureClassifying {
    nonisolated var libraryWriteWasRejected: Bool {
        switch self {
        case .validation, .paywall, .unauthorized: true
        case let .server(code, _): ["VALIDATION_ERROR", "NOT_FOUND", "CONFLICT", "FORBIDDEN"].contains(code)
        case .network, .decoding, .unknown: false
        }
    }
}
