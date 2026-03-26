import Foundation

/// Production implementation of `CommerceAPIClientProtocol`.
/// Delegates all HTTP communication to the shared `APIClientProtocol` instance,
/// translating commerce-specific calls into the appropriate `APIEndpoint` cases.
final class CommerceAPIClient: CommerceAPIClientProtocol {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - CommerceAPIClientProtocol

    func fetchProducts() async throws -> [StoreProductModel] {
        try await apiClient.request(.getCommerceProducts)
    }

    func fetchEntitlement() async throws -> EntitlementSnapshot {
        try await apiClient.request(.getEntitlement)
    }

    func createPurchaseAttempt(
        productId: String,
        placement: PaywallPlacement?
    ) async throws -> PurchaseAttemptResponse {
        let body = CreatePurchaseAttemptBody(
            productId: productId,
            placement: placement?.rawValue
        )
        return try await apiClient.request(.createPurchaseAttempt(body: body))
    }

    func syncTransaction(request: SyncTransactionRequest) async throws -> EntitlementSnapshot {
        try await apiClient.request(.syncTransaction(body: request))
    }

    func consumeUsage(metric: UsageMetricCode) async throws -> UsageBucket {
        let body = ConsumeUsageBody(metricCode: metric.rawValue)
        return try await apiClient.request(.checkUsage(body: body))
    }
}
